package com.ffmux.app.engine

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.ffmux.app.Graph
import com.ffmux.app.MainActivity
import com.ffmux.app.R
import com.ffmux.app.data.db.DownloadEntity
import com.ffmux.app.util.MimeUtils
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import java.io.File

/**
 * Foreground service that runs queued downloads one after another,
 * keeps the Room database up to date and posts progress notifications.
 * Every yt-dlp output line is mirrored into the terminal log kept by
 * [Graph], so the Downloads screen can show exactly what happened.
 */
class DownloadService : Service() {

    private val dao get() = Graph.db.downloadDao()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    @Volatile private var currentId: Long? = null
    @Volatile private var currentProcessId: String? = null
    @Volatile private var cancelCurrent = false

    private lateinit var notifications: NotificationManager

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        notifications = getSystemService(NotificationManager::class.java)
        createChannel()
        startForeground(NOTIFICATION_ID, buildProgressNotification("FFMux", "Preparing downloads...", 0))
        scope.launch {
            // Items left RUNNING by a killed process go back to the queue.
            dao.resetActive()
            runQueue()
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_CANCEL) {
            val id = intent.getLongExtra(EXTRA_ID, -1L)
            scope.launch { handleCancel(id) }
        }
        return START_STICKY
    }

    private suspend fun handleCancel(id: Long) {
        if (id == currentId) {
            cancelCurrent = true
            currentProcessId?.let { Graph.engine.destroyProcess(it) }
        } else {
            dao.cancelQueued(id)
        }
    }

    private suspend fun runQueue() {
        while (true) {
            val item = dao.claimNext()
            if (item == null) {
                delay(800)
                if (dao.nextQueued() == null) break
                continue
            }
            processItem(item)
        }
        notifications.cancel(NOTIFICATION_ID)
        stopSelf()
    }

    private suspend fun processItem(item: DownloadEntity) {
        currentId = item.id
        cancelCurrent = false
        val processId = "download_${item.id}"
        currentProcessId = processId
        Graph.clearLog(item.id)
        Graph.updateByteProgress(item.id, null)
        Graph.appendLog(item.id, "\$ yt-dlp -f ${item.formatSelector}")
        Graph.appendLog(item.id, "\$ url: ${item.url}")
        val tempDir = File(cacheDir, "downloads/${item.id}").apply { mkdirs() }
        val safeTitle = item.title
            .replace(Regex("[\\/:*?\"<>|%]"), "_")
            .trim()
            .take(80)
            .ifEmpty { "Untitled" }
        val template = "${tempDir.absolutePath}/$safeTitle.%(ext)s"

        updateNotification(item.title, "Starting...", 0)

        try {
            Graph.awaitEngine()

            var lastPercent = -1
            Graph.engine.download(item.url, item.formatSelector, processId, template) { progress, eta, line ->
                Graph.appendLog(item.id, line)
                parseByteProgress(line)?.let { Graph.updateByteProgress(item.id, it) }
                val percent = progress.toInt().coerceIn(0, 100)
                if (percent > lastPercent) {
                    lastPercent = percent
                    scope.launch {
                        dao.updateProgress(item.id, DownloadEntity.STATUS_RUNNING, progress, eta)
                        updateNotification(item.title, "Downloading... $percent%", percent)
                    }
                }
            }

            dao.setStatus(item.id, DownloadEntity.STATUS_SAVING)
            updateNotification(item.title, "Saving file...", -1)

            val file = tempDir.listFiles()?.firstOrNull { it.isFile }
                ?: throw IllegalStateException("Downloaded file not found")
            Graph.appendLog(item.id, "[ffmux] merging finished: ${file.name}")

            val treeUri = Graph.settings.treeUri.first()
            val savedUri = FileSaver.save(this, treeUri, file)
            val mime = MimeUtils.fromFileName(file.name)

            if (savedUri == null) {
                Graph.appendLog(item.id, "[ffmux] ERROR: could not save the file to the selected folder")
                dao.finishWithError(item.id, DownloadEntity.STATUS_FAILED, "Could not save the file to the selected folder")
            } else {
                Graph.appendLog(item.id, "[ffmux] saved to Downloads/FFMux")
                dao.finish(item.id, savedUri.toString())
                showCompletedNotification(item.id, item.title, savedUri, mime)
            }
            Graph.updateByteProgress(item.id, null)
            tempDir.deleteRecursively()
        } catch (e: Exception) {
            val status = if (cancelCurrent) DownloadEntity.STATUS_CANCELED else DownloadEntity.STATUS_FAILED
            val message = if (cancelCurrent) null else (e.message ?: "Download failed").take(300)
            Graph.appendLog(item.id, "ERROR: ${message ?: "canceled"}")
            Graph.updateByteProgress(item.id, null)
            dao.finishWithError(item.id, status, message)
            tempDir.deleteRecursively()
        } finally {
            currentId = null
            currentProcessId = null
        }
    }

    /**
     * Extracts "23.4% of 45.67MiB" from a yt-dlp progress line and turns it
     * into absolute downloaded/total byte counters for the progress bar.
     */
    private fun parseByteProgress(line: String): Graph.ByteProgress? {
        if (!line.startsWith("[download]") || !line.contains('%')) return null
        val sizeMatch = SIZE_IN_LINE.find(line) ?: return null
        val value = sizeMatch.groupValues[1].toDoubleOrNull() ?: return null
        val multiplier = when (sizeMatch.groupValues[2]) {
            "KiB", "KB" -> 1024.0
            "GiB", "GB" -> 1024.0 * 1024 * 1024
            else -> 1024.0 * 1024
        }
        val total = (value * multiplier).toLong()
        if (total <= 0L) return null
        val percent = PERCENT_IN_LINE.find(line)?.groupValues?.get(1)?.toDoubleOrNull() ?: return null
        val downloaded = ((percent / 100.0) * total).toLong().coerceAtMost(total)
        return Graph.ByteProgress(downloaded, total)
    }

    override fun onDestroy() {
        currentProcessId?.let { Graph.engine.destroyProcess(it) }
        scope.cancel()
        super.onDestroy()
    }

    private fun createChannel() {
        val channel = NotificationChannel(CHANNEL_ID, "Downloads", NotificationManager.IMPORTANCE_LOW).apply {
            description = "Progress of running downloads"
        }
        notifications.createNotificationChannel(channel)
    }

    private fun contentIntent(): PendingIntent =
        PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

    private fun buildProgressNotification(title: String, text: String, percent: Int): Notification =
        NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_download)
            .setContentTitle(title)
            .setContentText(text)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(contentIntent())
            .setProgress(100, percent, percent < 0)
            .build()

    private fun updateNotification(title: String, text: String, percent: Int) {
        notifications.notify(NOTIFICATION_ID, buildProgressNotification(title, text, percent))
    }

    private fun showCompletedNotification(id: Long, title: String, uri: Uri, mime: String) {
        val viewIntent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, mime)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        val pending = PendingIntent.getActivity(
            this,
            id.toInt(),
            viewIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_download)
            .setContentTitle("Download complete")
            .setContentText(title)
            .setAutoCancel(true)
            .setContentIntent(pending)
            .build()
        notifications.notify(COMPLETED_BASE_ID + id.toInt(), notification)
    }

    companion object {
        const val CHANNEL_ID = "downloads"
        const val NOTIFICATION_ID = 1
        const val COMPLETED_BASE_ID = 10000
        const val ACTION_CANCEL = "com.ffmux.app.action.CANCEL_DOWNLOAD"
        const val EXTRA_ID = "download_id"

        private val SIZE_IN_LINE =
            Regex("""of\s+~?\s*([\d.]+)\s*(KiB|MiB|GiB|KB|MB|GB)""")
        private val PERCENT_IN_LINE =
            Regex("""(\d{1,3}(?:\.\d+)?)%""")

        fun start(context: Context) {
            ContextCompat.startForegroundService(
                context,
                Intent(context, DownloadService::class.java)
            )
        }

        fun cancel(context: Context, id: Long) {
            context.startService(
                Intent(context, DownloadService::class.java)
                    .setAction(ACTION_CANCEL)
                    .putExtra(EXTRA_ID, id)
            )
        }
    }
}
