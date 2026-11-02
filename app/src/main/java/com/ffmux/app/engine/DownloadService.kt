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
        startForeground(NOTIFICATION_ID, buildProgressNotification("FFMux", "Preparing downloads…", 0))
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
        val tempDir = File(cacheDir, "downloads/${item.id}").apply { mkdirs() }
        val safeTitle = item.title
            .replace(Regex("[\\/:*?\"<>|%]"), "_")
            .trim()
            .take(80)
            .ifEmpty { "Untitled" }
        val template = "${tempDir.absolutePath}/$safeTitle.%(ext)s"

        // Patch 5: terminal log -- the command line plus every yt-dlp
        // output line, shown by the terminal button on the Downloads tab.
        val log = StringBuilder()
        fun logLine(line: String) {
            if (line.isBlank()) return
            log.appendLine(line.trimEnd())
            if (log.length > 24000) {
                log.delete(0, log.length - 20000)
            }
        }

        updateNotification(item.title, "Starting…", 0)
        logLine("\$ yt-dlp --no-playlist -f '${item.formatSelector}' ${item.url}")

        try {
            Graph.awaitEngine()

            var lastPercent = -1
            Graph.engine.download(item.url, item.formatSelector, processId, template) { progress, eta, line ->
                if (line.isNotBlank()) {
                    logLine(line)
                }
                val percent = progress.toInt().coerceIn(0, 100)
                if (percent > lastPercent) {
                    lastPercent = percent
                    val bytes = parseProgressBytes(line)
                    val snapshot = log.toString()
                    scope.launch {
                        dao.updateProgress(
                            item.id, DownloadEntity.STATUS_RUNNING, progress, eta,
                            bytes?.first, bytes?.second, snapshot
                        )
                        updateNotification(item.title, "Downloading… $percent%", percent)
                    }
                }
            }
            dao.updateLog(item.id, log.toString())

            dao.setStatus(item.id, DownloadEntity.STATUS_SAVING)
            updateNotification(item.title, "Saving file…", -1)

            val file = tempDir.listFiles()
                ?.filter { it.isFile && !it.name.endsWith(".part") && !it.name.endsWith(".ytdl") }
                ?.maxByOrNull { it.length() }
                ?: throw IllegalStateException("Downloaded file not found")

            val treeUri = Graph.settings.treeUri.first()
            val savedUri = FileSaver.save(this, treeUri, file)
            val mime = MimeUtils.fromFileName(file.name)

            if (savedUri == null) {
                dao.finishWithError(item.id, DownloadEntity.STATUS_FAILED, "Could not save the file to the selected folder")
                logLine("ERROR: could not save the file to the selected folder")
            } else {
                dao.finish(item.id, savedUri.toString())
                logLine("[ffmux] saved ${file.name} (${file.length()} bytes)")
                showCompletedNotification(item.id, item.title, savedUri, mime)
            }
            dao.updateLog(item.id, log.toString())
            tempDir.deleteRecursively()
        } catch (e: Exception) {
            val status = if (cancelCurrent) DownloadEntity.STATUS_CANCELED else DownloadEntity.STATUS_FAILED
            val message = if (cancelCurrent) null else (e.message ?: "Download failed").take(300)
            if (cancelCurrent) {
                logLine("[ffmux] canceled by user")
            } else {
                logLine("ERROR: ${e.message}")
            }
            dao.finishWithError(item.id, status, message)
            dao.updateLog(item.id, log.toString())
            tempDir.deleteRecursively()
        } finally {
            currentId = null
            currentProcessId = null
        }
    }

    /** Reads "[download] 51.3% of 9.6MiB"-style lines into byte counts. */
    private val progressLine = Regex(
        """\[\s*download\s*\]\s+(\d+(?:\.\d+)?)%\s+of\s+~?\s*([\d.]+)\s*(KiB|MiB|GiB|TiB|KB|MB|GB|TB)"""
    )

    private fun parseProgressBytes(line: String): Pair<Long, Long>? {
        val m = progressLine.find(line) ?: return null
        val percent = m.groupValues[1].toDoubleOrNull() ?: return null
        val value = m.groupValues[2].toDoubleOrNull() ?: return null
        val unit = when (m.groupValues[3]) {
            "KiB" -> 1024.0
            "MiB" -> 1048576.0
            "GiB" -> 1073741824.0
            "TiB" -> 1099511627776.0
            "KB" -> 1000.0
            "MB" -> 1000000.0
            "GB" -> 1000000000.0
            "TB" -> 1000000000000.0
            else -> return null
        }
        val total = (value * unit).toLong()
        if (total <= 0L) return null
        val downloaded = (total * percent / 100.0).toLong()
        return downloaded to total
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
