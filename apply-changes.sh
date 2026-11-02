#!/usr/bin/env bash
###############################################################################
# FFMux full source installer -- patches 1..7, cumulative and state-proof.
# Run from the repository root:  bash apply-changes.sh
#
# How this version works (different from patches 1-5):
#   Instead of editing the previous files in place, this script installs
#   the COMPLETE, build-tested Kotlin source of FFMux 1.4.0 over
#   app/src/main/java/. Whatever state your tree is in (fresh upstream
#   clone, patch 1, patch 2, ..., or a half-applied anything) the result
#   is byte-for-byte the tree that was compiled and verified before this
#   script was shipped. It also deletes stray .kt files left over from
#   earlier patches and bumps the app version. Running it twice changes
#   nothing (content-stable, so the CI commit step stays a no-op).
#
# What is inside (everything from before, plus):
#   Patch 1: Seal-style info card, duration badge, no About card,
#            sliding pill bottom navigation.
#   Patch 2: no press ripple on tabs, screen-size aware duration text,
#            150ms page crossfade, springier pill.
#   Patch 3: editable Title / Author, Best card, format spec chips,
#            Videocam / Audiotrack icons.
#   Patch 4: format list split into Video and Audio sections like Seal;
#            pick one card of each to merge with ffmpeg (selector
#            "137+140"); every card shows format ID, container, fps,
#            bitrate and estimated size; sticky Download bar above the
#            bottom navigation with the approximate final size.
#   Patch 5: Home keeps the link, the info and the selections after a
#            download is queued; yt-dlp retries (--retries 10,
#            --fragment-retries 10, --socket-timeout 30) and
#            --merge-output-format mp4/mkv against "errno 104 /
#            connection reset" and "postprocessing: conversion failed";
#            terminal log screen fed by the live yt-dlp output; dark
#            status bar icons in the light theme; retry button for
#            failed downloads; F-Droid style progress with percentage
#            and downloaded/total bytes.
#   Patch 6: log button moved to the far right of the "Downloads" header;
#            one shared header style (same size, same place) on Home,
#            Downloads and Settings; log screen text inset below the
#            status bar and above the navigation bar; progress block
#            keeps the exact same height before the download starts and
#            while it runs; taller quality cards.
#   Patch 7: no Paste button in the URL field any more (an X inside the
#            field clears it instead); the "Fetch info" button is
#            replaced by ONE BIG CIRCULAR button in the middle of the
#            page that pastes the clipboard link into the field and
#            fetches right away; the log screen is a dark terminal with
#            green monospace text, selectable lines, a copy-all button
#            and light system bar icons while it is open; yt-dlp option
#            chips under the quality cards, ytdlnis style: Thumbnail
#            (--embed-thumbnail), Subtitles (--embed-subs with a
#            language picker where English and Persian are pinned on
#            top), Metadata (--embed-metadata) and Chapters
#            (--split-chapters); Room db v2 migration carries the picked
#            flags inside every queue entry so they survive restarts.
#
# App version after this script: 1.4.0 (versionCode 7).
#
# Files replaced under app/src/main/java/com/ffmux/app/ (23 files):
#   FFMuxApp.kt  Graph.kt  MainActivity.kt
#   data/SettingsStore.kt  data/db/AppDatabase.kt  data/db/DownloadDao.kt
#   data/db/DownloadEntity.kt
#   engine/DownloadService.kt  engine/FileSaver.kt  engine/Models.kt
#   engine/YtDlpEngine.kt
#   ui/AppRoot.kt  ui/common/ScreenHeader.kt
#   ui/downloads/DownloadsScreen.kt  ui/downloads/DownloadsViewModel.kt
#   ui/downloads/LogScreen.kt
#   ui/home/HomeScreen.kt  ui/home/HomeViewModel.kt
#   ui/settings/SettingsScreen.kt  ui/settings/SettingsViewModel.kt
#   ui/theme/Theme.kt  util/MimeUtils.kt  util/UrlUtils.kt
# Also touched: app/build.gradle.kts (version bump only).
###############################################################################
set -euo pipefail

if LC_ALL=C grep -qn '[^ -~]' "$0"; then
  echo "FATAL: non-ascii byte in this script"
  exit 1
fi

BUILD_G="app/build.gradle.kts"
MANIFEST="app/src/main/AndroidManifest.xml"
for f in "$BUILD_G" "$MANIFEST" \
  "app/src/main/java/com/ffmux/app/FFMuxApp.kt" \
  "app/src/main/java/com/ffmux/app/Graph.kt"; do
  if [ ! -f "$f" ]; then
    echo "FATAL: $f not found - run from the repository root"
    exit 1
  fi
done

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

echo "== FFMux 1.4.0: installing full source (patches 1-7) =="
mkdir -p "$STAGE/com/ffmux/app"
cat > "$STAGE/com/ffmux/app/FFMuxApp.kt" <<'FFMUX_EOF_EA29CB2DBA'
package com.ffmux.app

import android.app.Application

class FFMuxApp : Application() {
    override fun onCreate() {
        super.onCreate()
        Graph.initialize(this)
    }
}
FFMUX_EOF_EA29CB2DBA
mkdir -p "$STAGE/com/ffmux/app"
cat > "$STAGE/com/ffmux/app/Graph.kt" <<'FFMUX_EOF_9D4ED47F1D'
package com.ffmux.app

import android.content.Context
import androidx.room.Room
import com.ffmux.app.data.SettingsStore
import com.ffmux.app.data.db.AppDatabase
import com.ffmux.app.engine.YtDlpEngine
import com.yausername.ffmpeg.FFmpeg
import com.yausername.youtubedl_android.YoutubeDL
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Tiny hand-rolled service locator: keeps the app free of a DI framework.
 */
object Graph {

    lateinit var db: AppDatabase
        private set
    lateinit var settings: SettingsStore
        private set
    lateinit var engine: YtDlpEngine
        private set

    val appScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    /** URL shared from another app, waiting to be picked up by the Home screen. */
    val pendingUrl = MutableStateFlow<String?>(null)

    /** True once the yt-dlp engine finished its one-time extraction. */
    val engineReady = MutableStateFlow(false)

    private var engineInit: Deferred<Unit>? = null

    /** Live downloaded/total byte counters of a running download, by id. */
    data class ByteProgress(val downloaded: Long = 0L, val total: Long = 0L)

    private val _byteProgress = MutableStateFlow<Map<Long, ByteProgress>>(emptyMap())
    val byteProgress: StateFlow<Map<Long, ByteProgress>> = _byteProgress.asStateFlow()

    private val _downloadLogs = MutableStateFlow<Map<Long, List<String>>>(emptyMap())
    val downloadLogs: StateFlow<Map<Long, List<String>>> = _downloadLogs.asStateFlow()

    private val logLock = Any()
    private const val MAX_LOG_LINES = 500
    private const val MAX_LOGGED_DOWNLOADS = 12

    /**
     * Appends one yt-dlp terminal line to the log of [id]. Consecutive
     * "[download] 12.3% ..." progress lines replace each other so the log
     * stays readable, and at most [MAX_LOG_LINES] lines are kept per download.
     */
    fun appendLog(id: Long, line: String) {
        val clean = line.trimEnd('\r', '\n')
        if (clean.isBlank()) return
        synchronized(logLock) {
            val logs = _downloadLogs.value.toMutableMap()
            val current = logs[id].orEmpty()
            val next: List<String> =
                if (isProgressLine(clean) && current.isNotEmpty() && isProgressLine(current.last())) {
                    current.dropLast(1) + clean
                } else {
                    current + clean
                }
            logs[id] = if (next.size > MAX_LOG_LINES) next.takeLast(MAX_LOG_LINES) else next
            if (logs.size > MAX_LOGGED_DOWNLOADS) {
                logs.keys.sorted().dropLast(MAX_LOGGED_DOWNLOADS).forEach { logs.remove(it) }
            }
            _downloadLogs.value = logs
        }
    }

    fun clearLog(id: Long) {
        synchronized(logLock) {
            _downloadLogs.value = _downloadLogs.value.toMutableMap().apply { remove(id) }
        }
    }

    fun logFor(id: Long): List<String> = _downloadLogs.value[id].orEmpty()

    fun updateByteProgress(id: Long, progress: ByteProgress?) {
        _byteProgress.value = _byteProgress.value.toMutableMap().apply {
            if (progress == null) remove(id) else put(id, progress)
        }
    }

    private fun isProgressLine(line: String): Boolean =
        line.startsWith("[download]") && line.contains('%')

    fun initialize(context: Context) {
        val app = context.applicationContext
        db = Room.databaseBuilder(app, AppDatabase::class.java, "ffmux.db")
            .addMigrations(AppDatabase.MIGRATION_1_2)
            .fallbackToDestructiveMigrationOnDowngrade()
            .build()
        settings = SettingsStore(app)
        engine = YtDlpEngine(app)

        synchronized(this) {
            if (engineInit == null) {
                engineInit = appScope.async(Dispatchers.IO) {
                    YoutubeDL.getInstance().init(app)
                    runCatching { FFmpeg.getInstance().init(app) }
                    engineReady.value = true
                }
            }
        }
    }

    suspend fun awaitEngine() {
        engineInit?.await()
    }
}
FFMUX_EOF_9D4ED47F1D
mkdir -p "$STAGE/com/ffmux/app"
cat > "$STAGE/com/ffmux/app/MainActivity.kt" <<'FFMUX_EOF_04287D2A4A'
package com.ffmux.app

import android.app.Activity
import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.platform.LocalView
import androidx.core.view.WindowCompat
import com.ffmux.app.ui.AppRoot
import com.ffmux.app.ui.theme.FFMuxTheme
import com.ffmux.app.util.UrlUtils

class MainActivity : ComponentActivity() {

    private val notificationPermission =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        requestNotificationPermissionIfNeeded()
        handleSharedIntent(intent)
        setContent {
            FFMuxTheme {
                // Dark status/navigation bar icons in the light theme, light
                // icons in the dark theme -- keeps them readable on Android 15
                // where edge-to-edge is enforced.
                val darkTheme = isSystemInDarkTheme()
                val view = LocalView.current
                if (!view.isInEditMode) {
                    SideEffect {
                        val window = (view.context as Activity).window
                        WindowCompat.getInsetsController(window, view).apply {
                            isAppearanceLightStatusBars = !darkTheme
                            isAppearanceLightNavigationBars = !darkTheme
                        }
                    }
                }
                AppRoot()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleSharedIntent(intent)
    }

    private fun handleSharedIntent(intent: Intent?) {
        if (intent?.action == Intent.ACTION_SEND && intent.type == "text/plain") {
            val text = intent.getStringExtra(Intent.EXTRA_TEXT) ?: return
            UrlUtils.extractFirstUrl(text)?.let { Graph.pendingUrl.value = it }
        }
    }

    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT >= 33) {
            val permission = Manifest.permission.POST_NOTIFICATIONS
            if (checkSelfPermission(permission) != PackageManager.PERMISSION_GRANTED) {
                notificationPermission.launch(permission)
            }
        }
    }
}
FFMUX_EOF_04287D2A4A
mkdir -p "$STAGE/com/ffmux/app/data"
cat > "$STAGE/com/ffmux/app/data/SettingsStore.kt" <<'FFMUX_EOF_0558C69B12'
package com.ffmux.app.data

import android.content.Context
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

private val Context.dataStore by preferencesDataStore(name = "settings")

class SettingsStore(private val context: Context) {

    private val treeUriKey = stringPreferencesKey("download_tree_uri")

    /** SAF tree uri of the user-chosen download folder, or null for the default. */
    val treeUri: Flow<String?> = context.dataStore.data.map { prefs -> prefs[treeUriKey] }

    suspend fun setTreeUri(uri: String?) {
        context.dataStore.edit { prefs ->
            if (uri == null) prefs.remove(treeUriKey) else prefs[treeUriKey] = uri
        }
    }
}
FFMUX_EOF_0558C69B12
mkdir -p "$STAGE/com/ffmux/app/data/db"
cat > "$STAGE/com/ffmux/app/data/db/AppDatabase.kt" <<'FFMUX_EOF_0B67FCA732'
package com.ffmux.app.data.db

import androidx.room.Database
import androidx.room.RoomDatabase
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase

@Database(entities = [DownloadEntity::class], version = 2, exportSchema = false)
abstract class AppDatabase : RoomDatabase() {
    abstract fun downloadDao(): DownloadDao

    companion object {
        /**
         * v1 -> v2: the downloads table gains the downloadArgs column that
         * carries the yt-dlp option flags picked on the Home screen.
         */
        val MIGRATION_1_2: Migration = object : Migration(1, 2) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL(
                    "ALTER TABLE downloads ADD COLUMN downloadArgs TEXT NOT NULL DEFAULT ''"
                )
            }
        }
    }
}
FFMUX_EOF_0B67FCA732
mkdir -p "$STAGE/com/ffmux/app/data/db"
cat > "$STAGE/com/ffmux/app/data/db/DownloadDao.kt" <<'FFMUX_EOF_9CF4E23D19'
package com.ffmux.app.data.db

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.Query
import androidx.room.Transaction
import kotlinx.coroutines.flow.Flow

@Dao
interface DownloadDao {

    @Insert
    suspend fun insert(item: DownloadEntity): Long

    @Query("SELECT * FROM downloads ORDER BY id DESC")
    fun observeAll(): Flow<List<DownloadEntity>>

    @Query("SELECT * FROM downloads WHERE id = :id")
    suspend fun findById(id: Long): DownloadEntity?

    @Query("SELECT * FROM downloads WHERE status = 'QUEUED' ORDER BY id LIMIT 1")
    suspend fun nextQueued(): DownloadEntity?

    @Query("UPDATE downloads SET status = 'RUNNING' WHERE id = :id AND status = 'QUEUED'")
    suspend fun markRunningIfQueued(id: Long): Int

    /** Atomically claims the next queued item so a late cancel cannot double-run it. */
    @Transaction
    suspend fun claimNext(): DownloadEntity? {
        val item = nextQueued() ?: return null
        return if (markRunningIfQueued(item.id) > 0) item else null
    }

    @Query("UPDATE downloads SET status = 'QUEUED', progress = 0 WHERE status IN ('RUNNING', 'SAVING')")
    suspend fun resetActive()

    /** Puts a failed or canceled download back into the queue for a retry. */
    @Query(
        "UPDATE downloads SET status = 'QUEUED', progress = 0, etaSec = NULL, " +
            "error = NULL, savedUri = NULL " +
            "WHERE id = :id AND status IN ('FAILED', 'CANCELED')"
    )
    suspend fun resetForRetry(id: Long): Int

    @Query("UPDATE downloads SET status = :status, progress = :progress, etaSec = :eta WHERE id = :id")
    suspend fun updateProgress(id: Long, status: String, progress: Float, eta: Long?)

    @Query("UPDATE downloads SET status = :status WHERE id = :id")
    suspend fun setStatus(id: Long, status: String)

    @Query("UPDATE downloads SET status = 'CANCELED' WHERE id = :id AND status = 'QUEUED'")
    suspend fun cancelQueued(id: Long)

    @Query("UPDATE downloads SET status = :status, error = :error WHERE id = :id")
    suspend fun finishWithError(id: Long, status: String, error: String?)

    @Query("UPDATE downloads SET status = 'COMPLETED', progress = 100, etaSec = NULL, savedUri = :uri WHERE id = :id")
    suspend fun finish(id: Long, uri: String?)

    @Query("DELETE FROM downloads WHERE id = :id")
    suspend fun delete(id: Long)
}
FFMUX_EOF_9CF4E23D19
mkdir -p "$STAGE/com/ffmux/app/data/db"
cat > "$STAGE/com/ffmux/app/data/db/DownloadEntity.kt" <<'FFMUX_EOF_1BD360E31A'
package com.ffmux.app.data.db

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "downloads")
data class DownloadEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0L,
    val url: String,
    val title: String,
    val thumbnail: String? = null,
    val uploader: String? = null,
    val durationSec: Long? = null,
    val formatSelector: String,
    val formatLabel: String,
    /** Extra yt-dlp flags chosen on the Home screen ("--embed-thumbnail ..."), */
    val downloadArgs: String = "",
    val status: String = STATUS_QUEUED,
    val progress: Float = 0f,
    val etaSec: Long? = null,
    val savedUri: String? = null,
    val error: String? = null,
    val createdAt: Long = 0L
) {
    companion object {
        const val STATUS_QUEUED = "QUEUED"
        const val STATUS_RUNNING = "RUNNING"
        const val STATUS_SAVING = "SAVING"
        const val STATUS_COMPLETED = "COMPLETED"
        const val STATUS_FAILED = "FAILED"
        const val STATUS_CANCELED = "CANCELED"
    }
}
FFMUX_EOF_1BD360E31A
mkdir -p "$STAGE/com/ffmux/app/engine"
cat > "$STAGE/com/ffmux/app/engine/DownloadService.kt" <<'FFMUX_EOF_413D94BD9A'
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
        val argsLine = if (item.downloadArgs.isBlank()) "" else " ${item.downloadArgs}"
        Graph.appendLog(item.id, "\$ yt-dlp -f ${item.formatSelector}$argsLine")
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
            Graph.engine.download(
                item.url, item.formatSelector, item.downloadArgs, processId, template
            ) { progress, eta, line ->
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
FFMUX_EOF_413D94BD9A
mkdir -p "$STAGE/com/ffmux/app/engine"
cat > "$STAGE/com/ffmux/app/engine/FileSaver.kt" <<'FFMUX_EOF_54B4AA738E'
package com.ffmux.app.engine

import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Environment
import android.provider.MediaStore
import androidx.documentfile.provider.DocumentFile
import com.ffmux.app.util.MimeUtils
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

/**
 * Moves a finished download from the private cache directory into
 * user-visible storage: either the SAF folder the user picked, or
 * the MediaStore Downloads collection by default.
 */
object FileSaver {

    suspend fun save(context: Context, treeUri: String?, file: File): Uri? =
        withContext(Dispatchers.IO) {
            val displayName = file.name
            val mime = MimeUtils.fromFileName(displayName)

            if (treeUri != null) {
                saveToSafTree(context, treeUri, file, displayName, mime)
            } else {
                saveToMediaStore(context, file, displayName, mime)
            }
        }

    private fun saveToSafTree(
        context: Context,
        treeUri: String,
        file: File,
        displayName: String,
        mime: String
    ): Uri? {
        val tree = DocumentFile.fromTreeUri(context, Uri.parse(treeUri)) ?: return null
        val target = tree.createFile(mime, displayName) ?: return null
        context.contentResolver.openOutputStream(target.uri)?.use { out ->
            file.inputStream().use { input -> input.copyTo(out) }
        }
        return target.uri
    }

    private fun saveToMediaStore(
        context: Context,
        file: File,
        displayName: String,
        mime: String
    ): Uri? {
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, displayName)
            put(MediaStore.MediaColumns.MIME_TYPE, mime)
            put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/FFMux")
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = context.contentResolver
            .insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values) ?: return null

        val copied = runCatching {
            context.contentResolver.openOutputStream(uri)?.use { out ->
                file.inputStream().use { input -> input.copyTo(out) }
            }
        }.isSuccess

        return if (copied) {
            values.clear()
            values.put(MediaStore.MediaColumns.IS_PENDING, 0)
            runCatching { context.contentResolver.update(uri, values, null, null) }
            uri
        } else {
            runCatching { context.contentResolver.delete(uri, null, null) }
            null
        }
    }
}
FFMUX_EOF_54B4AA738E
mkdir -p "$STAGE/com/ffmux/app/engine"
cat > "$STAGE/com/ffmux/app/engine/Models.kt" <<'FFMUX_EOF_2781D62188'
package com.ffmux.app.engine

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class VideoInfo(
    val id: String? = null,
    val title: String? = null,
    val uploader: String? = null,
    val duration: Long? = null,
    val thumbnail: String? = null,
    @SerialName("_type") val type: String? = null,
    val formats: List<VideoFormat> = emptyList()
)

@Serializable
data class VideoFormat(
    @SerialName("format_id") val formatId: String? = null,
    val ext: String? = null,
    val height: Int? = null,
    val fps: Double? = null,
    val vcodec: String? = null,
    val acodec: String? = null,
    val filesize: Long? = null,
    val tbr: Double? = null
)

enum class FormatKind { VIDEO, AUDIO }

data class FormatOption(
    val label: String,
    val selector: String,
    val kind: FormatKind,
    val formatId: String? = null,
    val ext: String? = null,
    val fps: Int? = null,
    val kbps: Int? = null,
    val size: String? = null,
    val sizeBytes: Long? = null,
    val note: String? = null
)

/**
 * The Home screen format list, split like Seal: one "Best" shortcut,
 * then video-only qualities and audio-only qualities in their own
 * sections so one card of each can be picked and merged.
 */
data class FormatSections(
    val best: FormatOption,
    val video: List<FormatOption>,
    val audio: List<FormatOption>
)
FFMUX_EOF_2781D62188
mkdir -p "$STAGE/com/ffmux/app/engine"
cat > "$STAGE/com/ffmux/app/engine/YtDlpEngine.kt" <<'FFMUX_EOF_D12B4524D4'
package com.ffmux.app.engine

import android.content.Context
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLRequest
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json

/**
 * Thin wrapper around the youtubedl-android library.
 * All public functions either suspend onto Dispatchers.IO or must be called from IO.
 */
class YtDlpEngine(private val appContext: Context) {

    private val json = Json {
        ignoreUnknownKeys = true
        isLenient = true
    }

    /** Fetches metadata for a single video (equivalent of `yt-dlp -J`). */
    suspend fun fetchInfo(url: String): VideoInfo = withContext(Dispatchers.IO) {
        val request = YoutubeDLRequest(url).apply {
            addOption("-J")
            addOption("--no-playlist")
            addOption("--retries", 10)
            addOption("--socket-timeout", 30)
        }
        val response = YoutubeDL.getInstance().execute(request)
        json.decodeFromString(response.out)
    }

    /**
     * Blocking download call. Runs yt-dlp with the chosen format selector and
     * reports progress through [onProgress]. Must be called from an IO dispatcher.
     *
     * [extraArgs] carries the option flags picked on the Home screen
     * ("--embed-thumbnail --convert-thumbnails jpg --embed-subs
     * --sub-langs en,fa ...") as one space separated string.
     *
     * Network resilience: yt-dlp retries each fragment/https error up to 10
     * times and uses a 30s socket timeout, so one reset connection
     * ("errno 104 connection reset by peer") no longer fails the download.
     * When the selector merges two streams ("137+140") ffmpeg is asked to
     * remux into mp4 with an mkv fallback, which avoids the
     * "postprocessing: conversion failed" error on mixed codecs.
     */
    fun download(
        url: String,
        selector: String,
        extraArgs: String,
        processId: String,
        outputTemplate: String,
        onProgress: (Float, Long, String) -> Unit
    ) {
        val request = YoutubeDLRequest(url).apply {
            addOption("--no-playlist")
            addOption("-f", selector)
            addOption("-o", outputTemplate)
            addOption("--no-mtime")
            addOption("--retries", 10)
            addOption("--fragment-retries", 10)
            addOption("--socket-timeout", 30)
            if (selector.contains('+')) {
                addOption("--merge-output-format", "mp4/mkv")
            }
            applyExtraArgs(extraArgs)
        }
        YoutubeDL.getInstance().execute(request, processId) { progress, eta, line ->
            onProgress(progress, eta, line)
        }
    }

    /**
     * Parses a space separated "--flag value" string into request options.
     * A token is treated as a valued option when the next token exists and
     * does not itself start with "--"; otherwise it is a plain flag.
     */
    private fun YoutubeDLRequest.applyExtraArgs(extra: String) {
        if (extra.isBlank()) return
        val tokens = extra.trim().split(Regex("\\s+"))
        var i = 0
        while (i < tokens.size) {
            val flag = tokens[i]
            val value = tokens.getOrNull(i + 1)
            if (flag.startsWith("--") && value != null && !value.startsWith("--")) {
                addOption(flag, value)
                i += 2
            } else {
                addOption(flag)
                i += 1
            }
        }
    }

    suspend fun currentVersion(): String = withContext(Dispatchers.IO) {
        runCatching { YoutubeDL.getInstance().version(appContext) }.getOrNull() ?: "unknown"
    }

    /**
     * Replaces the bundled yt-dlp binary with the latest stable release from
     * the official yt-dlp GitHub releases -- no app update required.
     */
    suspend fun update(): String = withContext(Dispatchers.IO) {
        try {
            when (YoutubeDL.getInstance()
                .updateYoutubeDL(appContext, YoutubeDL.UpdateChannel.STABLE)) {
                YoutubeDL.UpdateStatus.DONE -> "yt-dlp has been updated."
                YoutubeDL.UpdateStatus.ALREADY_UP_TO_DATE -> "yt-dlp is already up to date."
                else -> "yt-dlp is already up to date."
            }
        } catch (e: Exception) {
            throw IllegalStateException(e.message ?: "Update failed", e)
        }
    }

    fun destroyProcess(processId: String) {
        runCatching { YoutubeDL.getInstance().destroyProcessById(processId) }
    }

    companion object {

        /** Builds the video / audio format sections shown on the Home screen. */
        fun buildFormatSections(info: VideoInfo): FormatSections {
            val audioFormats = info.formats.filter {
                (it.vcodec == null || it.vcodec == "none") &&
                    !it.acodec.isNullOrEmpty() && it.acodec != "none"
            }
            val bestAudio = audioFormats.maxByOrNull { it.tbr ?: 0.0 }

            val heights = info.formats
                .filter { !it.vcodec.isNullOrEmpty() && it.vcodec != "none" && it.height != null }
                .map { it.height!! }
                .distinct()
                .sortedDescending()

            val video = heights.map { h ->
                val sample = info.formats
                    .filter { !it.vcodec.isNullOrEmpty() && it.vcodec != "none" && it.height == h }
                    .maxByOrNull { it.tbr ?: 0.0 }
                val bytes = estimatedBytes(sample, info.duration)
                FormatOption(
                    label = "${h}p",
                    selector = sample?.formatId?.takeIf { it.isNotBlank() }
                        ?: "bestvideo[height<=$h]",
                    kind = FormatKind.VIDEO,
                    formatId = sample?.formatId,
                    ext = sample?.ext?.uppercase(),
                    fps = sample?.fps?.toInt(),
                    kbps = sample?.tbr?.toInt(),
                    size = sizeText(bytes),
                    sizeBytes = bytes
                )
            }

            val audio = audioFormats.mapNotNull { it.ext }.distinct().sorted().map { e ->
                val sample = audioFormats.filter { it.ext == e }.maxByOrNull { it.tbr ?: 0.0 }
                val bytes = estimatedBytes(sample, info.duration)
                FormatOption(
                    label = e.uppercase(),
                    selector = sample?.formatId?.takeIf { it.isNotBlank() }
                        ?: "bestaudio[ext=$e]",
                    kind = FormatKind.AUDIO,
                    formatId = sample?.formatId,
                    ext = e.uppercase(),
                    kbps = sample?.tbr?.toInt(),
                    size = sizeText(bytes),
                    sizeBytes = bytes
                )
            }
            val audioOptions = if (audio.isEmpty()) {
                listOf(FormatOption("Audio", "bestaudio", FormatKind.AUDIO))
            } else {
                audio
            }

            val bestVideo = info.formats
                .filter { !it.vcodec.isNullOrEmpty() && it.vcodec != "none" }
                .maxWithOrNull(compareBy({ it.height ?: 0 }, { it.tbr ?: 0.0 }))
            val bestBytes =
                addSizes(estimatedBytes(bestVideo, info.duration), estimatedBytes(bestAudio, info.duration))
            val best = FormatOption(
                label = "Best",
                selector = "bestvideo*+bestaudio/best",
                kind = FormatKind.VIDEO,
                note = "Best video + audio",
                size = sizeText(bestBytes),
                sizeBytes = bestBytes
            )
            return FormatSections(best = best, video = video, audio = audioOptions)
        }

        /** File size in bytes: the reported value, else a tbr x duration estimate. */
        private fun estimatedBytes(format: VideoFormat?, duration: Long?): Long? {
            format ?: return null
            format.filesize?.let { return it }
            val tbr = format.tbr ?: return null
            val seconds = duration ?: return null
            return (tbr * 125.0 * seconds).toLong()
        }

        private fun addSizes(a: Long?, b: Long?): Long? =
            if (a != null && b != null) a + b else (a ?: b)

        private fun sizeText(bytes: Long?): String? {
            if (bytes == null) return null
            val mb = bytes / 1048576.0
            return when {
                mb >= 1024.0 -> String.format("%.1f GB", mb / 1024.0)
                mb >= 100.0 -> String.format("%.0f MB", mb)
                mb >= 1.0 -> String.format("%.1f MB", mb)
                else -> String.format("%.0f KB", bytes / 1024.0)
            }
        }
    }
}
FFMUX_EOF_D12B4524D4
mkdir -p "$STAGE/com/ffmux/app/ui"
cat > "$STAGE/com/ffmux/app/ui/AppRoot.kt" <<'FFMUX_EOF_2C73F3138D'
package com.ffmux.app.ui

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.keyframes
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.ffmux.app.ui.downloads.DownloadsScreen
import com.ffmux.app.ui.downloads.LogScreen
import com.ffmux.app.ui.home.HomeScreen
import com.ffmux.app.ui.settings.SettingsScreen

private data class Tab(
    val route: String,
    val label: String,
    val icon: ImageVector
)

private val tabs = listOf(
    Tab("home", "Home", Icons.Filled.Home),
    Tab("downloads", "Downloads", Icons.Filled.Download),
    Tab("settings", "Settings", Icons.Filled.Settings)
)

private val PillWidth = 64.dp
private val PillHeight = 32.dp
private val BarHeight = 80.dp
private val LabelSlotHeight = 24.dp

@Composable
fun AppRoot() {
    val navController = rememberNavController()
    val backStackEntry by navController.currentBackStackEntryAsState()
    val currentRoute = backStackEntry?.destination?.route
    val showBottomBar = tabs.any { it.route == currentRoute }

    Scaffold(
        bottomBar = {
            if (showBottomBar) {
                SlidingPillNavBar(
                    currentRoute = currentRoute,
                    onTabSelected = { route -> navController.navigateTab(route) }
                )
            }
        }
    ) { padding ->
        // The log screen draws its own dark terminal background edge to
        // edge, so it must NOT be inset by the scaffold padding; every
        // other route keeps the usual insets.
        val isLogRoute = currentRoute?.startsWith("log/") == true
        NavHost(
            navController = navController,
            startDestination = "home",
            modifier = Modifier
                .fillMaxSize()
                .then(
                    if (isLogRoute) Modifier else Modifier.padding(padding)
                ),
            enterTransition = { fadeIn(tween(150)) },
            exitTransition = { fadeOut(tween(100)) },
            popEnterTransition = { fadeIn(tween(150)) },
            popExitTransition = { fadeOut(tween(100)) }
        ) {
            composable("home") {
                HomeScreen(
                    onDownloadStarted = { navController.navigateTab("downloads") }
                )
            }
            composable("downloads") {
                DownloadsScreen(
                    onOpenLog = { id -> navController.navigate("log/$id") }
                )
            }
            composable("settings") { SettingsScreen() }
            composable(
                route = "log/{downloadId}",
                arguments = listOf(navArgument("downloadId") { type = NavType.LongType })
            ) { entry ->
                val downloadId = entry.arguments?.getLong("downloadId") ?: 0L
                LogScreen(
                    downloadId = downloadId,
                    onBack = { navController.popBackStack() }
                )
            }
        }
    }
}

@Composable
private fun SlidingPillNavBar(
    currentRoute: String?,
    onTabSelected: (String) -> Unit
) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        color = MaterialTheme.colorScheme.surfaceContainer,
        tonalElevation = 3.dp
    ) {
        BoxWithConstraints(
            modifier = Modifier
                .fillMaxWidth()
                .navigationBarsPadding()
                .height(BarHeight)
        ) {
            val tabWidth = maxWidth / tabs.size
            val selectedIndex =
                tabs.indexOfFirst { it.route == currentRoute }.coerceAtLeast(0)

            val pillOffset by animateDpAsState(
                targetValue = tabWidth * selectedIndex + (tabWidth - PillWidth) / 2,
                animationSpec = spring(
                    dampingRatio = Spring.DampingRatioLowBouncy,
                    stiffness = Spring.StiffnessMedium
                ),
                label = "pillOffset"
            )

            Column(modifier = Modifier.matchParentSize()) {
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxWidth()
                ) {
                    Box(
                        modifier = Modifier
                            .align(Alignment.CenterStart)
                            .offset(x = pillOffset)
                            .size(PillWidth, PillHeight)
                            .clip(CircleShape)
                            .background(MaterialTheme.colorScheme.secondaryContainer)
                    )
                }
                Spacer(modifier = Modifier.height(LabelSlotHeight))
            }

            Row(modifier = Modifier.fillMaxWidth()) {
                tabs.forEach { tab ->
                    NavTabItem(
                        tab = tab,
                        selected = currentRoute == tab.route,
                        onClick = { onTabSelected(tab.route) }
                    )
                }
            }
        }
    }
}

@Composable
private fun RowScope.NavTabItem(
    tab: Tab,
    selected: Boolean,
    onClick: () -> Unit
) {
    val scale = remember { Animatable(1f) }
    var firstComposition by remember { mutableStateOf(true) }

    LaunchedEffect(selected) {
        if (firstComposition) {
            firstComposition = false
            return@LaunchedEffect
        }
        if (selected) {
            scale.snapTo(1f)
            scale.animateTo(
                targetValue = 1f,
                animationSpec = keyframes {
                    durationMillis = 280
                    0.78f at 100 using FastOutSlowInEasing
                }
            )
        }
    }

    Column(
        modifier = Modifier
            .weight(1f)
            .fillMaxHeight()
            .selectable(
                selected = selected,
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
                onClick = onClick
            ),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Box(
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth(),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = tab.icon,
                contentDescription = tab.label,
                modifier = Modifier
                    .size(26.dp)
                    .scale(scale.value),
                tint = if (selected) MaterialTheme.colorScheme.onSecondaryContainer
                else MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        Box(
            modifier = Modifier.height(LabelSlotHeight),
            contentAlignment = Alignment.Center
        ) {
            Text(
                text = tab.label,
                style = MaterialTheme.typography.labelMedium,
                color = if (selected) MaterialTheme.colorScheme.onSecondaryContainer
                else MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1
            )
        }
    }
}

private fun androidx.navigation.NavHostController.navigateTab(route: String) {
    navigate(route) {
        popUpTo(graph.findStartDestination().id) {
            saveState = true
        }
        launchSingleTop = true
        restoreState = true
    }
}
FFMUX_EOF_2C73F3138D
mkdir -p "$STAGE/com/ffmux/app/ui/common"
cat > "$STAGE/com/ffmux/app/ui/common/ScreenHeader.kt" <<'FFMUX_EOF_4B31690609'
package com.ffmux.app.ui.common

import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

/**
 * One shared large title for every top-level screen: Home ("Download"),
 * Downloads and Settings all get the exact same style, height and 16dp
 * alignment, so the headers line up perfectly when switching tabs.
 *
 * Optional [actions] are pushed to the far right end of the row.
 */
@Composable
fun ScreenHeader(
    title: String,
    modifier: Modifier = Modifier,
    actions: @Composable RowScope.() -> Unit = {}
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .height(56.dp)
            .padding(start = 16.dp, end = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = title,
            style = MaterialTheme.typography.headlineMedium,
            maxLines = 1
        )
        Spacer(modifier = Modifier.weight(1f))
        actions()
    }
}
FFMUX_EOF_4B31690609
mkdir -p "$STAGE/com/ffmux/app/ui/downloads"
cat > "$STAGE/com/ffmux/app/ui/downloads/DownloadsScreen.kt" <<'FFMUX_EOF_128FE1D8A1'
package com.ffmux.app.ui.downloads

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.OpenInNew
import androidx.compose.material.icons.outlined.Terminal
import androidx.compose.material3.Card
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.ffmux.app.Graph
import com.ffmux.app.data.db.DownloadEntity
import com.ffmux.app.ui.common.ScreenHeader

@Composable
fun DownloadsScreen(
    onOpenLog: (Long) -> Unit,
    viewModel: DownloadsViewModel = viewModel()
) {
    val items by viewModel.items.collectAsStateWithLifecycle()
    val logs by Graph.downloadLogs.collectAsState()
    val liveBytes by Graph.byteProgress.collectAsState()
    val context = LocalContext.current

    Column(modifier = Modifier.fillMaxSize()) {
        ScreenHeader(
            title = "Downloads",
            actions = {
                // Terminal log button, pinned to the far right end of the row.
                if (items.isNotEmpty()) {
                    IconButton(onClick = {
                        items.firstOrNull()?.let { onOpenLog(it.id) }
                    }) {
                        Icon(
                            Icons.Outlined.Terminal,
                            contentDescription = "Terminal log"
                        )
                    }
                }
            }
        )

        if (items.isEmpty()) {
            Box(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth(),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    "No downloads yet.\nShare a link from any app,\nor paste one on the Home tab.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center
                )
            }
        } else {
            LazyColumn(
                modifier = Modifier.weight(1f),
                contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 4.dp, bottom = 16.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                items(items, key = { it.id }) { item ->
                    DownloadItemCard(
                        item = item,
                        liveBytes = liveBytes[item.id],
                        hasLog = !logs[item.id].orEmpty().isEmpty(),
                        onCancel = { viewModel.cancel(item.id) },
                        onDelete = { viewModel.delete(item.id) },
                        onOpen = {
                            item.savedUri?.let { openSavedFile(context, it) }
                        },
                        onRetry = { viewModel.retry(item.id) },
                        onOpenLog = { onOpenLog(item.id) }
                    )
                }
            }
        }
    }
}

@Composable
private fun DownloadItemCard(
    item: DownloadEntity,
    liveBytes: Graph.ByteProgress?,
    hasLog: Boolean,
    onCancel: () -> Unit,
    onDelete: () -> Unit,
    onOpen: () -> Unit,
    onRetry: () -> Unit,
    onOpenLog: () -> Unit
) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            Text(
                item.title,
                style = MaterialTheme.typography.titleSmall,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            Text(
                "${item.formatLabel} \u00B7 ${statusText(item)}",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            when (item.status) {
                DownloadEntity.STATUS_QUEUED,
                DownloadEntity.STATUS_RUNNING,
                DownloadEntity.STATUS_SAVING -> ProgressBlock(item, liveBytes)
                else -> {}
            }
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.End,
                verticalAlignment = Alignment.CenterVertically
            ) {
                if (item.status == DownloadEntity.STATUS_FAILED ||
                    item.status == DownloadEntity.STATUS_CANCELED
                ) {
                    IconButton(onClick = onRetry) {
                        Icon(Icons.Filled.Refresh, contentDescription = "Retry")
                    }
                }
                if (hasLog) {
                    IconButton(onClick = onOpenLog) {
                        Icon(Icons.Outlined.Terminal, contentDescription = "Terminal log")
                    }
                }
                if (item.status == DownloadEntity.STATUS_QUEUED ||
                    item.status == DownloadEntity.STATUS_RUNNING ||
                    item.status == DownloadEntity.STATUS_SAVING
                ) {
                    IconButton(onClick = onCancel) {
                        Icon(Icons.Filled.Close, contentDescription = "Cancel")
                    }
                }
                if (item.status == DownloadEntity.STATUS_COMPLETED) {
                    IconButton(onClick = onOpen) {
                        Icon(Icons.Outlined.OpenInNew, contentDescription = "Open")
                    }
                }
                IconButton(onClick = onDelete) {
                    Icon(Icons.Outlined.Delete, contentDescription = "Delete")
                }
            }
        }
    }
}

/**
 * F-Droid style progress: a fat determinate bar plus one status line with
 * percentage and downloaded/total bytes. The bar keeps the exact same
 * height in every state (waiting, starting, downloading, saving) so the
 * card never jumps when the download starts.
 */
@Composable
private fun ProgressBlock(item: DownloadEntity, liveBytes: Graph.ByteProgress?) {
    val determinate = item.status == DownloadEntity.STATUS_RUNNING && item.progress > 0f
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        if (determinate) {
            LinearProgressIndicator(
                progress = { (item.progress / 100f).coerceIn(0f, 1f) },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(8.dp)
            )
        } else {
            LinearProgressIndicator(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(8.dp)
            )
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                text = progressLabel(item, liveBytes),
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f)
            )
            if (determinate) {
                item.etaSec?.takeIf { it > 0 }?.let { eta ->
                    Text(
                        text = "ETA ${formatEta(eta)}",
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }
    }
}

private fun progressLabel(item: DownloadEntity, live: Graph.ByteProgress?): String =
    when (item.status) {
        DownloadEntity.STATUS_QUEUED -> "Waiting in queue..."
        DownloadEntity.STATUS_RUNNING -> when {
            item.progress <= 0f -> "Starting..."
            live != null && live.total > 0 ->
                "${item.progress.toInt()}% \u00B7 ${byteText(live.downloaded)} / ${byteText(live.total)}"
            else -> "${item.progress.toInt()}%"
        }
        DownloadEntity.STATUS_SAVING -> "Saving file..."
        else -> ""
    }

private fun byteText(bytes: Long): String {
    val mb = bytes / 1048576.0
    return when {
        mb >= 1024.0 -> String.format("%.2f GB", mb / 1024.0)
        mb >= 10.0 -> String.format("%.1f MB", mb)
        mb >= 0.01 -> String.format("%.1f MB", mb)
        else -> String.format("%.0f KB", bytes / 1024.0)
    }
}

private fun formatEta(seconds: Long): String {
    val h = seconds / 3600
    val m = (seconds % 3600) / 60
    val s = seconds % 60
    return if (h > 0) {
        String.format("%d:%02d:%02d", h, m, s)
    } else {
        String.format("%d:%02d", m, s)
    }
}

private fun statusText(item: DownloadEntity): String = when (item.status) {
    DownloadEntity.STATUS_QUEUED -> "Queued"
    DownloadEntity.STATUS_RUNNING -> "Downloading"
    DownloadEntity.STATUS_SAVING -> "Saving"
    DownloadEntity.STATUS_COMPLETED -> "Completed"
    DownloadEntity.STATUS_CANCELED -> "Canceled"
    DownloadEntity.STATUS_FAILED -> item.error?.let { "Failed \u2014 ${it.take(60)}" } ?: "Failed"
    else -> item.status
}

private fun openSavedFile(context: Context, uriString: String) {
    val uri = Uri.parse(uriString)
    val intent = Intent(Intent.ACTION_VIEW).apply {
        setDataAndType(uri, "*/*")
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }
    runCatching { context.startActivity(intent) }
}
FFMUX_EOF_128FE1D8A1
mkdir -p "$STAGE/com/ffmux/app/ui/downloads"
cat > "$STAGE/com/ffmux/app/ui/downloads/DownloadsViewModel.kt" <<'FFMUX_EOF_9C55FC4AC8'
package com.ffmux.app.ui.downloads

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.ffmux.app.Graph
import com.ffmux.app.engine.DownloadService
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

class DownloadsViewModel(application: Application) : AndroidViewModel(application) {

    val items = Graph.db.downloadDao()
        .observeAll()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    fun cancel(id: Long) {
        DownloadService.cancel(getApplication(), id)
    }

    fun delete(id: Long) {
        viewModelScope.launch(Dispatchers.IO) {
            Graph.db.downloadDao().delete(id)
        }
    }

    /** Puts a failed or canceled download back into the queue. */
    fun retry(id: Long) {
        viewModelScope.launch(Dispatchers.IO) {
            Graph.clearLog(id)
            val requeued = Graph.db.downloadDao().resetForRetry(id)
            if (requeued > 0) {
                DownloadService.start(getApplication())
            }
        }
    }
}
FFMUX_EOF_9C55FC4AC8
mkdir -p "$STAGE/com/ffmux/app/ui/downloads"
cat > "$STAGE/com/ffmux/app/ui/downloads/LogScreen.kt" <<'FFMUX_EOF_FFFD26C0AF'
package com.ffmux.app.ui.downloads

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.widget.Toast
import androidx.compose.foundation.background
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.view.WindowCompat
import com.ffmux.app.Graph

/** Terminal look of the log: always dark, green monospace text. */
private val LogBackground = Color(0xFF0A0F0A)
private val LogTextGreen = Color(0xFF4AF626)
private val LogDimGreen = Color(0xFF8FBF9F)
private val LogHeaderText = Color(0xFFD8F3D8)

/**
 * Full terminal log of one download: every yt-dlp output line, live.
 * The screen is drawn edge to edge with its own dark background, so it
 * insets itself below the status bar and above the navigation bar, and
 * switches the system bar icons to light while it is open. Any line can
 * be long-pressed for text selection and the header button copies the
 * whole log to the clipboard.
 */
@Composable
fun LogScreen(
    downloadId: Long,
    onBack: () -> Unit
) {
    val logs by Graph.downloadLogs.collectAsState()
    val lines = logs[downloadId].orEmpty()
    val clipboard = LocalClipboardManager.current
    val context = LocalContext.current
    val listState = rememberLazyListState()
    var title by remember { mutableStateOf("") }

    // The log is always dark: force light system bar icons while it is
    // visible, restore the theme icons when it goes away.
    val view = LocalView.current
    val systemDark = isSystemInDarkTheme()
    DisposableEffect(systemDark) {
        val window = view.context.findActivity()?.window
        val controller = window?.let { WindowCompat.getInsetsController(it, view) }
        controller?.isAppearanceLightStatusBars = false
        controller?.isAppearanceLightNavigationBars = false
        onDispose {
            controller?.isAppearanceLightStatusBars = !systemDark
            controller?.isAppearanceLightNavigationBars = !systemDark
        }
    }

    LaunchedEffect(downloadId) {
        title = Graph.db.downloadDao().findById(downloadId)?.title.orEmpty()
    }
    LaunchedEffect(lines.size) {
        if (lines.isNotEmpty()) listState.animateScrollToItem(lines.size - 1)
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(LogBackground)
            .statusBarsPadding()
            .navigationBarsPadding()
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .height(56.dp)
                .padding(start = 8.dp, end = 8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            IconButton(onClick = onBack) {
                Icon(
                    Icons.AutoMirrored.Filled.ArrowBack,
                    contentDescription = "Back",
                    tint = LogHeaderText
                )
            }
            Text(
                text = "Terminal log",
                style = MaterialTheme.typography.titleLarge,
                color = LogHeaderText,
                maxLines = 1
            )
            Spacer(modifier = Modifier.weight(1f))
            IconButton(
                onClick = {
                    clipboard.setText(AnnotatedString(lines.joinToString("\n")))
                    Toast.makeText(context, "Log copied to clipboard", Toast.LENGTH_SHORT).show()
                },
                enabled = lines.isNotEmpty()
            ) {
                Icon(
                    Icons.Outlined.ContentCopy,
                    contentDescription = "Copy log",
                    tint = LogHeaderText
                )
            }
        }
        if (title.isNotBlank()) {
            Text(
                text = title,
                style = MaterialTheme.typography.bodySmall,
                color = LogDimGreen,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.padding(horizontal = 16.dp)
            )
        }

        if (lines.isEmpty()) {
            Box(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth(),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    "No terminal output for this download yet.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = LogDimGreen,
                    textAlign = TextAlign.Center
                )
            }
        } else {
            SelectionContainer {
                LazyColumn(
                    state = listState,
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxWidth(),
                    contentPadding = PaddingValues(
                        start = 16.dp, end = 16.dp, top = 10.dp, bottom = 16.dp
                    ),
                    verticalArrangement = Arrangement.spacedBy(1.dp)
                ) {
                    itemsIndexed(lines) { _, line ->
                        Text(
                            text = line,
                            fontFamily = FontFamily.Monospace,
                            fontSize = 11.sp,
                            lineHeight = 15.sp,
                            color = LogTextGreen,
                            modifier = Modifier.padding(vertical = 1.dp)
                        )
                    }
                }
            }
        }
    }
}

private tailrec fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findActivity()
    else -> null
}
FFMUX_EOF_FFFD26C0AF
mkdir -p "$STAGE/com/ffmux/app/ui/home"
cat > "$STAGE/com/ffmux/app/ui/home/HomeScreen.kt" <<'FFMUX_EOF_33E8F0E06A'
package com.ffmux.app.ui.home

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.rounded.Audiotrack
import androidx.compose.material.icons.rounded.ContentCut
import androidx.compose.material.icons.rounded.Download
import androidx.compose.material.icons.rounded.Image
import androidx.compose.material.icons.rounded.Label
import androidx.compose.material.icons.rounded.PushPin
import androidx.compose.material.icons.rounded.Subtitles
import androidx.compose.material.icons.rounded.Videocam
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import coil.compose.AsyncImage
import com.ffmux.app.Graph
import com.ffmux.app.engine.FormatKind
import com.ffmux.app.engine.FormatOption
import com.ffmux.app.engine.VideoInfo
import com.ffmux.app.ui.common.ScreenHeader
import com.ffmux.app.util.UrlUtils

@Composable
fun HomeScreen(
    onDownloadStarted: () -> Unit,
    viewModel: HomeViewModel = viewModel()
) {
    val clipboard = LocalClipboardManager.current
    val engineReady by Graph.engineReady.collectAsState()

    // One circular action: when the field is empty the clipboard link is
    // pasted in first, then the video info is fetched right away.
    val onFetchClicked: () -> Unit = {
        if (viewModel.url.isBlank()) {
            val text = clipboard.getText()?.text ?: ""
            UrlUtils.extractFirstUrl(text)?.let { pasted ->
                viewModel.updateUrl(pasted)
            }
        }
        viewModel.fetch()
    }

    Column(modifier = Modifier.fillMaxSize()) {
        ScreenHeader(title = "Download")

        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp)
        ) {
            if (!engineReady) {
                LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
                Text(
                    "Preparing the yt-dlp engine... (first launch only)",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            OutlinedTextField(
                value = viewModel.url,
                onValueChange = { viewModel.updateUrl(it) },
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Video URL") },
                singleLine = true,
                trailingIcon = {
                    if (viewModel.url.isNotEmpty()) {
                        IconButton(onClick = { viewModel.updateUrl("") }) {
                            Icon(Icons.Filled.Close, contentDescription = "Clear")
                        }
                    }
                }
            )
        }

        val current = viewModel.state
        // Keep the fetched info on screen while a re-fetch is running or
        // when it fails, so the format list never collapses.
        var lastInfo by remember { mutableStateOf<HomeUiState.Info?>(null) }
        (current as? HomeUiState.Info)?.let { lastInfo = it }
        val infoState = current as? HomeUiState.Info ?: lastInfo
        val loading = current is HomeUiState.Loading
        val errorState = current as? HomeUiState.Error

        if (infoState != null) {
            Column(
                modifier = Modifier
                    .weight(1f)
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                CircularFetchButton(loading = loading, onClick = onFetchClicked)

                errorState?.let {
                    Text(
                        text = it.message,
                        color = MaterialTheme.colorScheme.error,
                        style = MaterialTheme.typography.bodyMedium,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.fillMaxWidth()
                    )
                }

                InfoCard(
                    info = infoState.info,
                    title = viewModel.editableTitle,
                    onTitleChange = { viewModel.updateTitle(it) },
                    uploader = viewModel.editableUploader,
                    onUploaderChange = { viewModel.updateUploader(it) }
                )

                Text("Format", style = MaterialTheme.typography.titleMedium)
                BestCard(
                    option = infoState.sections.best,
                    selected = viewModel.bestSelected,
                    onClick = { viewModel.selectBest() }
                )

                if (infoState.sections.video.isNotEmpty()) {
                    Text("Video", style = MaterialTheme.typography.titleMedium)
                    FormatGrid(
                        options = infoState.sections.video,
                        selected = viewModel.selectedVideo,
                        onToggle = { viewModel.toggleVideo(it) }
                    )
                }

                if (infoState.sections.audio.isNotEmpty()) {
                    Text("Audio", style = MaterialTheme.typography.titleMedium)
                    FormatGrid(
                        options = infoState.sections.audio,
                        selected = viewModel.selectedAudio,
                        onToggle = { viewModel.toggleAudio(it) }
                    )
                }

                Text("Options", style = MaterialTheme.typography.titleMedium)
                OptionChips(
                    embedThumbnail = viewModel.embedThumbnail,
                    onThumbnailToggle = { viewModel.toggleEmbedThumbnail() },
                    embedMetadata = viewModel.embedMetadata,
                    onMetadataToggle = { viewModel.toggleEmbedMetadata() },
                    splitChapters = viewModel.splitChapters,
                    onChaptersToggle = { viewModel.toggleSplitChapters() },
                    subLangs = viewModel.subLangs,
                    onSubLangsChange = { viewModel.updateSubLangs(it) }
                )
                Spacer(Modifier.height(8.dp))
            }

            StickyDownloadBar(
                enabled = viewModel.selectedSelector() != null,
                sizeBytes = viewModel.selectedSizeBytes(),
                videoOnly = viewModel.isVideoOnlySelection(),
                onClick = { viewModel.startDownload(onDownloadStarted) }
            )
        } else {
            // Idle / loading / error: the big circular button sits in
            // the middle of the free page area.
            Box(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth(),
                contentAlignment = Alignment.Center
            ) {
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    modifier = Modifier.padding(horizontal = 24.dp)
                ) {
                    CircularFetchButton(loading = loading, onClick = onFetchClicked)
                    if (errorState != null) {
                        Spacer(Modifier.height(20.dp))
                        Text(
                            text = errorState.message,
                            color = MaterialTheme.colorScheme.error,
                            style = MaterialTheme.typography.bodyMedium,
                            textAlign = TextAlign.Center
                        )
                    }
                }
            }
        }
    }
}

/**
 * Big circular main action in the middle of the page: pastes the
 * clipboard link into the field when it is empty, then fetches the
 * video info. While fetching it turns into a spinner.
 */
@Composable
private fun CircularFetchButton(
    loading: Boolean,
    onClick: () -> Unit
) {
    Box(
        modifier = Modifier.fillMaxWidth(),
        contentAlignment = Alignment.Center
    ) {
        FilledIconButton(
            onClick = onClick,
            enabled = !loading,
            modifier = Modifier.size(76.dp),
            shape = androidx.compose.foundation.shape.CircleShape
        ) {
            if (loading) {
                CircularProgressIndicator(
                    modifier = Modifier.size(30.dp),
                    strokeWidth = 3.dp,
                    color = MaterialTheme.colorScheme.onPrimary
                )
            } else {
                Icon(
                    imageVector = Icons.Rounded.Download,
                    contentDescription = "Paste link and fetch",
                    modifier = Modifier.size(34.dp)
                )
            }
        }
    }
}

/** One yt-dlp feature toggle chip, ytdlnis style. */
@Composable
private fun OptionChip(
    label: String,
    icon: ImageVector,
    selected: Boolean,
    onClick: () -> Unit
) {
    val animatedOutline by animateColorAsState(
        targetValue = if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outlineVariant,
        animationSpec = tween(100), label = "chipOutline"
    )
    val animatedContainer by animateColorAsState(
        targetValue = if (selected) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surface,
        animationSpec = tween(100), label = "chipContainer"
    )
    val animatedTitle by animateColorAsState(
        targetValue = if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface,
        animationSpec = tween(100), label = "chipTitle"
    )
    Row(
        modifier = Modifier
            .clip(androidx.compose.foundation.shape.CircleShape)
            .selectable(selected = selected, onClick = onClick)
            .border(1.dp, animatedOutline, androidx.compose.foundation.shape.CircleShape)
            .background(animatedContainer)
            .padding(start = 14.dp, end = 18.dp, top = 10.dp, bottom = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Icon(icon, contentDescription = null, tint = animatedOutline, modifier = Modifier.size(16.dp))
        Text(label, style = MaterialTheme.typography.labelLarge, color = animatedTitle)
    }
}

/** Row of yt-dlp option chips shown under the quality cards. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun OptionChips(
    embedThumbnail: Boolean,
    onThumbnailToggle: () -> Unit,
    embedMetadata: Boolean,
    onMetadataToggle: () -> Unit,
    splitChapters: Boolean,
    onChaptersToggle: () -> Unit,
    subLangs: Set<String>,
    onSubLangsChange: (Set<String>) -> Unit
) {
    var showSubDialog by rememberSaveable { mutableStateOf(false) }

    FlowRow(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        OptionChip(
            label = "Thumbnail",
            icon = Icons.Rounded.Image,
            selected = embedThumbnail,
            onClick = onThumbnailToggle
        )
        OptionChip(
            label = subLangsLabel(subLangs),
            icon = Icons.Rounded.Subtitles,
            selected = subLangs.isNotEmpty(),
            onClick = { showSubDialog = true }
        )
        OptionChip(
            label = "Metadata",
            icon = Icons.Rounded.Label,
            selected = embedMetadata,
            onClick = onMetadataToggle
        )
        OptionChip(
            label = "Chapters",
            icon = Icons.Rounded.ContentCut,
            selected = splitChapters,
            onClick = onChaptersToggle
        )
    }

    if (showSubDialog) {
        SubtitleLangDialog(
            selected = subLangs,
            onDismiss = { showSubDialog = false },
            onConfirm = { langs ->
                onSubLangsChange(langs)
                showSubDialog = false
            }
        )
    }
}

private fun subLangsLabel(langs: Set<String>): String {
    if (langs.isEmpty()) return "Subtitles"
    return "Subtitles " + langs.sorted().joinToString(",")
}

private data class SubLang(val code: String, val name: String)

/** English and Persian are pinned to the top of the list. */
private val pinnedSubLangs = listOf(
    SubLang("en", "English"),
    SubLang("fa", "Persian")
)

private val otherSubLangs = listOf(
    SubLang("ar", "Arabic"),
    SubLang("de", "German"),
    SubLang("es", "Spanish"),
    SubLang("fr", "French"),
    SubLang("hi", "Hindi"),
    SubLang("id", "Indonesian"),
    SubLang("it", "Italian"),
    SubLang("ja", "Japanese"),
    SubLang("ko", "Korean"),
    SubLang("nl", "Dutch"),
    SubLang("pl", "Polish"),
    SubLang("pt", "Portuguese"),
    SubLang("ru", "Russian"),
    SubLang("tr", "Turkish"),
    SubLang("ur", "Urdu"),
    SubLang("zh-Hans", "Chinese (Simplified)")
)

/**
 * Multi-select list of subtitle languages to embed into the video
 * (--embed-subs --sub-langs ...). English and Persian sit pinned at
 * the top, every other common language follows below the divider.
 */
@Composable
private fun SubtitleLangDialog(
    selected: Set<String>,
    onDismiss: () -> Unit,
    onConfirm: (Set<String>) -> Unit
) {
    var picked by remember { mutableStateOf(selected) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Embed subtitles") },
        text = {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(max = 340.dp)
                    .verticalScroll(rememberScrollState())
            ) {
                Text(
                    "Pick the subtitle languages to embed into the video file.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Spacer(Modifier.height(10.dp))
                pinnedSubLangs.forEach { lang ->
                    SubLangRow(
                        lang = lang,
                        pinned = true,
                        checked = lang.code in picked,
                        onToggle = {
                            picked = if (lang.code in picked) picked - lang.code else picked + lang.code
                        }
                    )
                }
                HorizontalDivider(
                    modifier = Modifier.padding(vertical = 6.dp),
                    color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f)
                )
                otherSubLangs.forEach { lang ->
                    SubLangRow(
                        lang = lang,
                        pinned = false,
                        checked = lang.code in picked,
                        onToggle = {
                            picked = if (lang.code in picked) picked - lang.code else picked + lang.code
                        }
                    )
                }
            }
        },
        confirmButton = {
            TextButton(onClick = { onConfirm(picked) }) { Text("Done") }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Cancel") }
        }
    )
}

@Composable
private fun SubLangRow(
    lang: SubLang,
    pinned: Boolean,
    checked: Boolean,
    onToggle: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(MaterialTheme.shapes.extraSmall)
            .selectable(selected = checked, onClick = onToggle)
            .padding(vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Checkbox(checked = checked, onCheckedChange = null)
        Spacer(Modifier.width(10.dp))
        Column {
            Text(lang.name, style = MaterialTheme.typography.bodyLarge)
            Text(
                lang.code,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        Spacer(Modifier.weight(1f))
        if (pinned) {
            Icon(
                imageVector = Icons.Rounded.PushPin,
                contentDescription = "Pinned",
                modifier = Modifier.size(14.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

@Composable
private fun InfoCard(
    info: VideoInfo,
    title: String,
    onTitleChange: (String) -> Unit,
    uploader: String,
    onUploaderChange: (String) -> Unit
) {
    ElevatedCard(
        modifier = Modifier.fillMaxWidth(),
        shape = MaterialTheme.shapes.small
    ) {
        Column {
            Box(Modifier.fillMaxWidth()) {
                AsyncImage(
                    model = info.thumbnail,
                    contentDescription = null,
                    modifier = Modifier
                        .fillMaxWidth()
                        .aspectRatio(16f / 9f, matchHeightConstraintsFirst = true)
                        .clip(MaterialTheme.shapes.small),
                    contentScale = ContentScale.Crop
                )
                info.duration?.let { seconds ->
                    val config = LocalConfiguration.current
                    val durationFontSize =
                        (config.screenWidthDp * 0.038f).coerceIn(12f, 18f).sp
                    Surface(
                        modifier = Modifier
                            .padding(6.dp)
                            .align(Alignment.BottomEnd),
                        color = Color.Black.copy(alpha = 0.68f),
                        shape = MaterialTheme.shapes.extraSmall
                    ) {
                        Text(
                            modifier = Modifier.padding(horizontal = 6.dp, vertical = 1.dp),
                            text = formatDuration(seconds),
                            fontSize = durationFontSize,
                            lineHeight = (durationFontSize.value * 1.15f).sp,
                            fontWeight = FontWeight.Medium,
                            color = Color.White
                        )
                    }
                }
            }
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(12.dp),
                horizontalAlignment = Alignment.Start
            ) {
                OutlinedTextField(
                    value = title,
                    onValueChange = onTitleChange,
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("Title") },
                    singleLine = true,
                    textStyle = MaterialTheme.typography.titleMedium,
                    shape = MaterialTheme.shapes.small,
                    trailingIcon = {
                        Icon(
                            Icons.Outlined.Edit,
                            contentDescription = null,
                            modifier = Modifier.size(16.dp),
                            tint = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                )
                OutlinedTextField(
                    value = uploader,
                    onValueChange = onUploaderChange,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = 8.dp),
                    label = { Text("Author") },
                    singleLine = true,
                    textStyle = MaterialTheme.typography.bodyMedium,
                    shape = MaterialTheme.shapes.small
                )
            }
        }
    }
}

/** Full-width shortcut card for the combined best video + audio format. */
@Composable
private fun BestCard(
    option: FormatOption,
    selected: Boolean,
    onClick: () -> Unit
) {
    val outlineColor = MaterialTheme.colorScheme.primary
    val containerColor = MaterialTheme.colorScheme.primaryContainer
    val animatedOutline by animateColorAsState(
        targetValue = if (selected) outlineColor else MaterialTheme.colorScheme.outlineVariant,
        animationSpec = tween(100), label = "bestOutline"
    )
    val animatedContainer by animateColorAsState(
        targetValue = if (selected) containerColor else MaterialTheme.colorScheme.surface,
        animationSpec = tween(100), label = "bestContainer"
    )
    val animatedTitle by animateColorAsState(
        targetValue = if (selected) outlineColor else MaterialTheme.colorScheme.onSurface,
        animationSpec = tween(100), label = "bestTitle"
    )
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 64.dp)
            .clip(MaterialTheme.shapes.small)
            .selectable(selected = selected, onClick = onClick)
            .border(1.dp, animatedOutline, MaterialTheme.shapes.small)
            .background(animatedContainer)
    ) {
        Row(
            modifier = Modifier
                .align(Alignment.CenterStart)
                .padding(start = 14.dp, top = 10.dp, bottom = 10.dp, end = 48.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                imageVector = Icons.Rounded.Videocam,
                contentDescription = "Video",
                tint = animatedOutline,
                modifier = Modifier.size(18.dp)
            )
            Icon(
                imageVector = Icons.Rounded.Audiotrack,
                contentDescription = "Audio",
                tint = animatedOutline,
                modifier = Modifier
                    .size(18.dp)
                    .padding(start = 2.dp)
            )
            Spacer(Modifier.width(10.dp))
            Column {
                Text(
                    text = option.label,
                    style = MaterialTheme.typography.titleSmall,
                    color = animatedTitle,
                    maxLines = 1
                )
                bestSpec(option)?.let {
                    Text(
                        text = it,
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
            }
        }
    }
}

/** Two-column grid of quality cards for one section. */
@Composable
private fun FormatGrid(
    options: List<FormatOption>,
    selected: Int,
    onToggle: (Int) -> Unit
) {
    options.chunked(2).forEachIndexed { rowIndex, rowOptions ->
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            rowOptions.forEachIndexed { colIndex, option ->
                val index = rowIndex * 2 + colIndex
                FormatCard(
                    option = option,
                    selected = selected == index,
                    onClick = { onToggle(index) },
                    modifier = Modifier.weight(1f)
                )
            }
            if (rowOptions.size == 1) {
                Spacer(modifier = Modifier.weight(1f))
            }
        }
    }
}

@Composable
private fun FormatCard(
    option: FormatOption,
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    val video = option.kind == FormatKind.VIDEO
    val outlineColor: Color
    val containerColor: Color
    if (video) {
        outlineColor = MaterialTheme.colorScheme.primary
        containerColor = MaterialTheme.colorScheme.primaryContainer
    } else {
        outlineColor = MaterialTheme.colorScheme.secondary
        containerColor = MaterialTheme.colorScheme.secondaryContainer
    }
    val animatedOutline by animateColorAsState(
        targetValue = if (selected) outlineColor else MaterialTheme.colorScheme.outlineVariant,
        animationSpec = tween(100), label = "formatOutline"
    )
    val animatedContainer by animateColorAsState(
        targetValue = if (selected) containerColor else MaterialTheme.colorScheme.surface,
        animationSpec = tween(100), label = "formatContainer"
    )
    val animatedTitle by animateColorAsState(
        targetValue = if (selected) outlineColor else MaterialTheme.colorScheme.onSurface,
        animationSpec = tween(100), label = "formatTitle"
    )
    Box(
        modifier = modifier
            .heightIn(min = 88.dp)
            .clip(MaterialTheme.shapes.small)
            .selectable(selected = selected, onClick = onClick)
            .border(1.dp, animatedOutline, MaterialTheme.shapes.small)
            .background(animatedContainer)
    ) {
        Column(
            modifier = Modifier.padding(start = 12.dp, top = 12.dp, end = 12.dp, bottom = 28.dp)
        ) {
            Text(
                text = option.label,
                style = MaterialTheme.typography.titleSmall,
                color = animatedTitle,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            specLine1(option)?.let {
                Text(
                    text = it,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
            specLine2(option)?.let {
                Text(
                    text = it,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
        }
        Row(
            modifier = Modifier
                .align(Alignment.BottomEnd)
                .padding(6.dp),
            horizontalArrangement = Arrangement.spacedBy(2.dp)
        ) {
            if (video) {
                Icon(
                    imageVector = Icons.Rounded.Videocam,
                    contentDescription = "Video",
                    tint = animatedOutline,
                    modifier = Modifier.size(14.dp)
                )
            } else {
                Icon(
                    imageVector = Icons.Rounded.Audiotrack,
                    contentDescription = "Audio",
                    tint = animatedOutline,
                    modifier = Modifier.size(14.dp)
                )
            }
        }
    }
}

/** Sticky bar pinned above the bottom navigation while formats are shown. */
@Composable
private fun StickyDownloadBar(
    enabled: Boolean,
    sizeBytes: Long?,
    videoOnly: Boolean,
    onClick: () -> Unit
) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        color = MaterialTheme.colorScheme.surfaceContainer,
        tonalElevation = 3.dp
    ) {
        Button(
            onClick = onClick,
            enabled = enabled,
            modifier = Modifier
                .fillMaxWidth()
                .padding(start = 16.dp, end = 16.dp, top = 12.dp, bottom = 12.dp)
                .height(56.dp),
            shape = MaterialTheme.shapes.large
        ) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(
                    text = "Download",
                    style = MaterialTheme.typography.titleMedium
                )
                Text(
                    text = downloadBarSubtitle(sizeBytes, videoOnly, enabled),
                    style = MaterialTheme.typography.labelMedium,
                    color = androidx.compose.material3.LocalContentColor.current.copy(alpha = 0.75f)
                )
            }
        }
    }
}

private fun downloadBarSubtitle(sizeBytes: Long?, videoOnly: Boolean, enabled: Boolean): String {
    if (!enabled) return "Select a format above"
    val parts = mutableListOf<String>()
    if (videoOnly) parts.add("video only, no audio")
    when {
        sizeBytes == null -> {}
        else -> parts.add(0, "approx. ${byteSizeText(sizeBytes)}")
    }
    return if (parts.isEmpty()) "Ready to download" else parts.joinToString(" \u00B7 ")
}

private fun byteSizeText(bytes: Long): String {
    val mb = bytes / 1048576.0
    return when {
        mb >= 1024.0 -> String.format("%.1f GB", mb / 1024.0)
        mb >= 100.0 -> String.format("%.0f MB", mb)
        mb >= 1.0 -> String.format("%.1f MB", mb)
        else -> String.format("%.0f KB", bytes / 1024.0)
    }
}

private fun bestSpec(option: FormatOption): String? {
    val parts = mutableListOf<String>()
    option.note?.let { parts.add(it) }
    option.size?.let { parts.add("~$it") }
    if (parts.isEmpty()) return null
    return parts.joinToString(" \u00B7 ")
}

private fun specLine1(option: FormatOption): String? {
    val parts = mutableListOf<String>()
    option.formatId?.let { parts.add("ID $it") }
    option.ext?.let { parts.add(it) }
    if (option.kind == FormatKind.VIDEO) {
        option.fps?.let { parts.add("${it}fps") }
    }
    if (parts.isEmpty()) return null
    return parts.joinToString(" \u00B7 ")
}

private fun specLine2(option: FormatOption): String? {
    val parts = mutableListOf<String>()
    option.size?.let { parts.add("~$it") }
    option.kbps?.let { parts.add("${it} kbps") }
    if (parts.isEmpty()) return null
    return parts.joinToString(" \u00B7 ")
}

private fun formatDuration(seconds: Long): String {
    val h = seconds / 3600
    val m = (seconds % 3600) / 60
    val s = seconds % 60
    return if (h > 0) {
        String.format("%d:%02d:%02d", h, m, s)
    } else {
        String.format("%d:%02d", m, s)
    }
}
FFMUX_EOF_33E8F0E06A
mkdir -p "$STAGE/com/ffmux/app/ui/home"
cat > "$STAGE/com/ffmux/app/ui/home/HomeViewModel.kt" <<'FFMUX_EOF_3AFD6E7F54'
package com.ffmux.app.ui.home

import android.app.Application
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.ffmux.app.Graph
import com.ffmux.app.data.db.DownloadEntity
import com.ffmux.app.engine.DownloadService
import com.ffmux.app.engine.FormatSections
import com.ffmux.app.engine.VideoInfo
import com.ffmux.app.engine.YtDlpEngine
import kotlinx.coroutines.launch

sealed interface HomeUiState {
    data object Idle : HomeUiState
    data object Loading : HomeUiState
    data class Error(val message: String) : HomeUiState
    data class Info(val info: VideoInfo, val sections: FormatSections) : HomeUiState
}

/**
 * Home screen state holder. The URL, the fetched video info and the
 * quality selections SURVIVE starting a download and switching tabs:
 * nothing is reset when a download is queued, so coming back from the
 * Downloads tab shows the same video and picks again.
 */
class HomeViewModel(application: Application) : AndroidViewModel(application) {

    var url by mutableStateOf("")
        private set
    var state by mutableStateOf<HomeUiState>(HomeUiState.Idle)
        private set

    /** True while the "Best" shortcut card is the active selection. */
    var bestSelected by mutableStateOf(true)
        private set

    /** Index into HomeUiState.Info.sections.video, -1 = none. */
    var selectedVideo by mutableStateOf(-1)
        private set

    /** Index into HomeUiState.Info.sections.audio, -1 = none. */
    var selectedAudio by mutableStateOf(-1)
        private set

    var editableTitle by mutableStateOf("")
        private set
    var editableUploader by mutableStateOf("")
        private set

    /** yt-dlp extras picked under the quality cards (ytdlnis style). */
    var embedThumbnail by mutableStateOf(false)
        private set
    var embedMetadata by mutableStateOf(false)
        private set
    var splitChapters by mutableStateOf(false)
        private set

    /** Selected subtitle languages (yt-dlp codes), empty = no subtitles. */
    var subLangs by mutableStateOf(setOf<String>())
        private set

    fun updateTitle(value: String) {
        editableTitle = value
    }

    fun updateUploader(value: String) {
        editableUploader = value
    }

    init {
        viewModelScope.launch {
            Graph.pendingUrl.collect { shared ->
                if (!shared.isNullOrBlank()) {
                    url = shared
                    Graph.pendingUrl.value = null
                    fetch()
                }
            }
        }
    }

    fun updateUrl(value: String) {
        url = value
    }

    fun toggleEmbedThumbnail() {
        embedThumbnail = !embedThumbnail
    }

    fun toggleEmbedMetadata() {
        embedMetadata = !embedMetadata
    }

    fun toggleSplitChapters() {
        splitChapters = !splitChapters
    }

    fun updateSubLangs(langs: Set<String>) {
        subLangs = langs
    }

    /**
     * Extra yt-dlp arguments for the current option toggles, as one
     * space separated "--flag value" string. Parsed back by the engine
     * right before the download runs, so the chosen flags travel inside
     * the queue entity and survive app restarts.
     */
    fun buildDownloadArgs(): String {
        val args = mutableListOf<String>()
        if (embedThumbnail) {
            args.add("--embed-thumbnail")
            args.add("--convert-thumbnails")
            args.add("jpg")
        }
        if (subLangs.isNotEmpty()) {
            args.add("--embed-subs")
            args.add("--sub-langs")
            args.add(subLangs.sorted().joinToString(","))
        }
        if (embedMetadata) args.add("--embed-metadata")
        if (splitChapters) args.add("--split-chapters")
        return args.joinToString(" ")
    }

    fun selectBest() {
        bestSelected = true
        selectedVideo = -1
        selectedAudio = -1
    }

    fun toggleVideo(index: Int) {
        bestSelected = false
        selectedVideo = if (selectedVideo == index) -1 else index
    }

    fun toggleAudio(index: Int) {
        bestSelected = false
        selectedAudio = if (selectedAudio == index) -1 else index
    }

    fun fetch() {
        val target = url.trim()
        if (target.isBlank()) return
        state = HomeUiState.Loading
        viewModelScope.launch {
            try {
                Graph.awaitEngine()
                val info = Graph.engine.fetchInfo(target)
                if (info.type == "playlist") {
                    state = HomeUiState.Error("Playlist links are not supported yet.")
                    return@launch
                }
                val sections = YtDlpEngine.buildFormatSections(info)
                if (sections.video.isEmpty() && sections.audio.isEmpty()) {
                    state = HomeUiState.Error("No downloadable formats found.")
                    return@launch
                }
                bestSelected = true
                selectedVideo = -1
                selectedAudio = -1
                editableTitle = info.title ?: "Untitled"
                editableUploader = info.uploader ?: ""
                state = HomeUiState.Info(info, sections)
            } catch (e: Exception) {
                state = HomeUiState.Error((e.message ?: "Could not fetch video info.").take(300))
            }
        }
    }

    /** The yt-dlp format selector for the current selection, or null. */
    fun selectedSelector(): String? {
        val current = state as? HomeUiState.Info ?: return null
        val video = current.sections.video.getOrNull(selectedVideo)
        val audio = current.sections.audio.getOrNull(selectedAudio)
        return when {
            bestSelected -> current.sections.best.selector
            video != null && audio != null -> "${video.selector}+${audio.selector}"
            video != null -> video.selector
            audio != null -> audio.selector
            else -> null
        }
    }

    /** True when a video-only stream is picked without any audio stream. */
    fun isVideoOnlySelection(): Boolean {
        if (bestSelected) return false
        val current = state as? HomeUiState.Info ?: return false
        return selectedVideo >= 0 && selectedAudio < 0 && current.sections.video.isNotEmpty()
    }

    /** Short label of the current selection, shown in the Downloads list. */
    fun selectedLabel(): String {
        val current = state as? HomeUiState.Info ?: return ""
        val video = current.sections.video.getOrNull(selectedVideo)
        val audio = current.sections.audio.getOrNull(selectedAudio)
        return when {
            bestSelected -> "Best"
            video != null && audio != null -> "${video.label} + ${audio.label}"
            video != null -> "${video.label} (video only)"
            audio != null -> audio.label
            else -> ""
        }
    }

    /** Estimated byte size of the resulting file, or null when unknown. */
    fun selectedSizeBytes(): Long? {
        val current = state as? HomeUiState.Info ?: return null
        val video = current.sections.video.getOrNull(selectedVideo)
        val audio = current.sections.audio.getOrNull(selectedAudio)
        return when {
            bestSelected -> current.sections.best.sizeBytes
            video != null && audio != null ->
                if (video.sizeBytes != null && audio.sizeBytes != null) {
                    video.sizeBytes!! + audio.sizeBytes!!
                } else {
                    video.sizeBytes ?: audio.sizeBytes
                }
            video != null -> video.sizeBytes
            audio != null -> audio.sizeBytes
            else -> null
        }
    }

    fun startDownload(onQueued: () -> Unit) {
        val current = state as? HomeUiState.Info ?: return
        val selector = selectedSelector() ?: return
        val info = current.info
        val target = url.trim()
        val label = selectedLabel().ifBlank { "Best" }

        viewModelScope.launch {
            val entity = DownloadEntity(
                url = target,
                title = editableTitle.ifBlank { info.title ?: "Untitled" },
                thumbnail = info.thumbnail,
                uploader = editableUploader.ifBlank { info.uploader },
                durationSec = info.duration,
                formatSelector = selector,
                formatLabel = label,
                downloadArgs = buildDownloadArgs(),
                createdAt = System.currentTimeMillis()
            )
            Graph.db.downloadDao().insert(entity)
            DownloadService.start(getApplication())
            // Intentionally NOT clearing url / state / selections here:
            // the user asked for the previous link and formats to stay.
            onQueued()
        }
    }
}
FFMUX_EOF_3AFD6E7F54
mkdir -p "$STAGE/com/ffmux/app/ui/settings"
cat > "$STAGE/com/ffmux/app/ui/settings/SettingsScreen.kt" <<'FFMUX_EOF_2D6EEFDBB6'
package com.ffmux.app.ui.settings

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.ffmux.app.ui.common.ScreenHeader

@Composable
fun SettingsScreen(viewModel: SettingsViewModel = viewModel()) {
    val treeUri by viewModel.treeUri.collectAsStateWithLifecycle()

    val folderPicker = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocumentTree()
    ) { uri ->
        if (uri != null) viewModel.chooseFolder(uri)
    }

    Column(modifier = Modifier.fillMaxSize()) {
        ScreenHeader(title = "Settings")

        Column(
            modifier = Modifier
                .weight(1f)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Text("Storage", style = MaterialTheme.typography.titleMedium)
                    Text("Download folder", style = MaterialTheme.typography.bodyLarge)
                    Text(
                        folderLabel(treeUri),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        TextButton(onClick = { folderPicker.launch(null) }) {
                            Text("Choose folder")
                        }
                        if (treeUri != null) {
                            TextButton(onClick = { viewModel.resetFolder() }) {
                                Text("Use default")
                            }
                        }
                    }
                    Text(
                        "By default files are saved to Downloads/FFMux.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }

            Card(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Text("yt-dlp engine", style = MaterialTheme.typography.titleMedium)
                    Text(
                        "Current version: ${viewModel.engineVersion ?: "loading..."}",
                        style = MaterialTheme.typography.bodyMedium
                    )
                    Button(
                        onClick = { viewModel.checkForUpdate() },
                        enabled = !viewModel.updating,
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        if (viewModel.updating) {
                            CircularProgressIndicator(
                                modifier = Modifier.size(18.dp),
                                strokeWidth = 2.dp
                            )
                            Spacer(Modifier.width(8.dp))
                            Text("Updating...")
                        } else {
                            Text("Check for updates")
                        }
                    }
                    viewModel.updateMessage?.let {
                        Text(
                            it,
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.primary
                        )
                    }
                }
            }
            Spacer(Modifier.height(8.dp))
        }
    }
}

private fun folderLabel(treeUri: String?): String {
    if (treeUri == null) return "Default (Downloads/FFMux)"
    return runCatching {
        val uri = Uri.parse(treeUri)
        val segment = uri.lastPathSegment ?: return "Custom folder"
        val name = segment.substringAfterLast(':').substringAfterLast('/')
        if (name.isBlank()) "Custom folder" else name
    }.getOrDefault("Custom folder")
}
FFMUX_EOF_2D6EEFDBB6
mkdir -p "$STAGE/com/ffmux/app/ui/settings"
cat > "$STAGE/com/ffmux/app/ui/settings/SettingsViewModel.kt" <<'FFMUX_EOF_98744F9CE5'
package com.ffmux.app.ui.settings

import android.app.Application
import android.content.Intent
import android.net.Uri
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.ffmux.app.Graph
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

class SettingsViewModel(application: Application) : AndroidViewModel(application) {

    val treeUri = Graph.settings.treeUri
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), null)

    var engineVersion by mutableStateOf<String?>(null)
        private set
    var updating by mutableStateOf(false)
        private set
    var updateMessage by mutableStateOf<String?>(null)
        private set

    init {
        viewModelScope.launch {
            runCatching { Graph.awaitEngine() }
            engineVersion = Graph.engine.currentVersion()
        }
    }

    fun chooseFolder(uri: Uri) {
        val app = getApplication<Application>()
        runCatching {
            app.contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            )
        }
        viewModelScope.launch {
            Graph.settings.setTreeUri(uri.toString())
        }
    }

    fun resetFolder() {
        viewModelScope.launch {
            Graph.settings.setTreeUri(null)
        }
    }

    fun checkForUpdate() {
        if (updating) return
        updating = true
        updateMessage = null
        viewModelScope.launch {
            try {
                Graph.awaitEngine()
                updateMessage = Graph.engine.update()
                engineVersion = Graph.engine.currentVersion()
            } catch (e: Exception) {
                updateMessage = "Update failed: ${(e.message ?: "unknown error").take(200)}"
            } finally {
                updating = false
            }
        }
    }
}
FFMUX_EOF_98744F9CE5
mkdir -p "$STAGE/com/ffmux/app/ui/theme"
cat > "$STAGE/com/ffmux/app/ui/theme/Theme.kt" <<'FFMUX_EOF_247E6A1517'
package com.ffmux.app.ui.theme

import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalContext

@Composable
fun FFMuxTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    dynamicColor: Boolean = true,
    content: @Composable () -> Unit
) {
    val colorScheme = when {
        dynamicColor && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {
            val context = LocalContext.current
            if (darkTheme) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        }
        darkTheme -> darkColorScheme()
        else -> lightColorScheme()
    }
    MaterialTheme(colorScheme = colorScheme, content = content)
}
FFMUX_EOF_247E6A1517
mkdir -p "$STAGE/com/ffmux/app/util"
cat > "$STAGE/com/ffmux/app/util/MimeUtils.kt" <<'FFMUX_EOF_BD330C64AC'
package com.ffmux.app.util

object MimeUtils {

    fun fromFileName(name: String): String {
        val ext = name.substringAfterLast('.', "").lowercase()
        return when (ext) {
            "mp4", "m4v" -> "video/mp4"
            "mkv" -> "video/x-matroska"
            "webm" -> "video/webm"
            "mov" -> "video/quicktime"
            "avi" -> "video/x-msvideo"
            "ts" -> "video/mp2t"
            "flv" -> "video/x-flv"
            "3gp" -> "video/3gpp"
            "m4a" -> "audio/mp4"
            "mp3" -> "audio/mpeg"
            "opus" -> "audio/opus"
            "ogg", "oga" -> "audio/ogg"
            "wav" -> "audio/x-wav"
            "flac" -> "audio/flac"
            "weba" -> "audio/webm"
            "aac" -> "audio/aac"
            else -> "application/octet-stream"
        }
    }
}
FFMUX_EOF_BD330C64AC
mkdir -p "$STAGE/com/ffmux/app/util"
cat > "$STAGE/com/ffmux/app/util/UrlUtils.kt" <<'FFMUX_EOF_CF24C7B007'
package com.ffmux.app.util

object UrlUtils {

    private val urlRegex = Regex("""https?://\S+""")

    fun extractFirstUrl(text: String): String? =
        urlRegex.find(text)?.value
            ?.trimEnd('.', ',', ';', ')')
            ?.takeIf { it.isNotBlank() }
}
FFMUX_EOF_CF24C7B007

# ---------------------------------------------------------------------------
# Install the staged sources over the tree (full replacement).
# ---------------------------------------------------------------------------
install_file() {
  dest="app/src/main/java/$1"
  mkdir -p "$(dirname "$dest")"
  cp -f "$STAGE/$1" "$dest"
}
install_file "com/ffmux/app/FFMuxApp.kt"
install_file "com/ffmux/app/Graph.kt"
install_file "com/ffmux/app/MainActivity.kt"
install_file "com/ffmux/app/data/SettingsStore.kt"
install_file "com/ffmux/app/data/db/AppDatabase.kt"
install_file "com/ffmux/app/data/db/DownloadDao.kt"
install_file "com/ffmux/app/data/db/DownloadEntity.kt"
install_file "com/ffmux/app/engine/DownloadService.kt"
install_file "com/ffmux/app/engine/FileSaver.kt"
install_file "com/ffmux/app/engine/Models.kt"
install_file "com/ffmux/app/engine/YtDlpEngine.kt"
install_file "com/ffmux/app/ui/AppRoot.kt"
install_file "com/ffmux/app/ui/common/ScreenHeader.kt"
install_file "com/ffmux/app/ui/downloads/DownloadsScreen.kt"
install_file "com/ffmux/app/ui/downloads/DownloadsViewModel.kt"
install_file "com/ffmux/app/ui/downloads/LogScreen.kt"
install_file "com/ffmux/app/ui/home/HomeScreen.kt"
install_file "com/ffmux/app/ui/home/HomeViewModel.kt"
install_file "com/ffmux/app/ui/settings/SettingsScreen.kt"
install_file "com/ffmux/app/ui/settings/SettingsViewModel.kt"
install_file "com/ffmux/app/ui/theme/Theme.kt"
install_file "com/ffmux/app/util/MimeUtils.kt"
install_file "com/ffmux/app/util/UrlUtils.kt"

# ---------------------------------------------------------------------------
# Remove stray .kt files that are not part of the managed set (leftovers
# from earlier patch generations), then prune empty directories.
# ---------------------------------------------------------------------------
KNOWN="com/ffmux/app/FFMuxApp.kt com/ffmux/app/Graph.kt com/ffmux/app/MainActivity.kt com/ffmux/app/data/SettingsStore.kt com/ffmux/app/data/db/AppDatabase.kt com/ffmux/app/data/db/DownloadDao.kt com/ffmux/app/data/db/DownloadEntity.kt com/ffmux/app/engine/DownloadService.kt com/ffmux/app/engine/FileSaver.kt com/ffmux/app/engine/Models.kt com/ffmux/app/engine/YtDlpEngine.kt com/ffmux/app/ui/AppRoot.kt com/ffmux/app/ui/common/ScreenHeader.kt com/ffmux/app/ui/downloads/DownloadsScreen.kt com/ffmux/app/ui/downloads/DownloadsViewModel.kt com/ffmux/app/ui/downloads/LogScreen.kt com/ffmux/app/ui/home/HomeScreen.kt com/ffmux/app/ui/home/HomeViewModel.kt com/ffmux/app/ui/settings/SettingsScreen.kt com/ffmux/app/ui/settings/SettingsViewModel.kt com/ffmux/app/ui/theme/Theme.kt com/ffmux/app/util/MimeUtils.kt com/ffmux/app/util/UrlUtils.kt"
find app/src/main/java -type f -name '*.kt' -print0 | while IFS= read -r -d '' f; do
  rel="${f#app/src/main/java/}"
  case " $KNOWN " in
    *" $rel "*) ;;
    *) echo "  [remove] stray source: $rel"; rm -f "$f" ;;
  esac
done
find app/src/main/java -type d -empty -delete 2>/dev/null || true

# ---------------------------------------------------------------------------
# Version bump (idempotent).
# ---------------------------------------------------------------------------
python3 - <<'PYEOF'
import re

BUILD_G = "app/build.gradle.kts"

def rd(p):
    with open(p, "r", encoding="utf-8") as f:
        return f.read()

src = rd(BUILD_G)
if "versionCode = 7" in src and 'versionName = "1.4.0"' in src:
    print("  [skip] BUILD: already 1.4.0 / code 7")
else:
    new = re.sub(r"versionCode = \d+", "versionCode = 7", src, count=1)
    new = re.sub(r'versionName = "[^"]*"', 'versionName = "1.4.0"', new, count=1)
    if new == src:
        raise SystemExit("FATAL: could not find version fields in " + BUILD_G)
    with open(BUILD_G, "w", encoding="utf-8") as f:
        f.write(new)
    print("  [applied] BUILD: versionName -> 1.4.0, versionCode -> 7")
PYEOF

# ---------------------------------------------------------------------------
# Gates: verify the installed tree before declaring success.
# ---------------------------------------------------------------------------
python3 - <<'PYEOF'
import os
import sys

BUILD_G = "app/build.gradle.kts"
MANIFEST = "app/src/main/AndroidManifest.xml"

passed = 0
failed = 0

def gate(name, ok, detail=""):
    global passed, failed
    if ok:
        passed += 1
        print("  [gate ok] " + name)
    else:
        failed += 1
        print("  [gate FAIL] " + name + (" -- " + detail if detail else ""))

def rd(p):
    with open(p, "r", encoding="utf-8") as f:
        return f.read()

GATES = {
    "com/ffmux/app/FFMuxApp.kt": [
        "Graph.initialize(this)"
    ],
    "com/ffmux/app/Graph.kt": [
        "val downloadLogs",
        "fun appendLog",
        "data class ByteProgress",
        "fallbackToDestructiveMigrationOnDowngrade()"
    ],
    "com/ffmux/app/MainActivity.kt": [
        "enableEdgeToEdge()",
        "isAppearanceLightStatusBars = !darkTheme",
        "isAppearanceLightNavigationBars = !darkTheme"
    ],
    "com/ffmux/app/data/SettingsStore.kt": [
        "class SettingsStore"
    ],
    "com/ffmux/app/data/db/AppDatabase.kt": [
        "version = 2",
        "MIGRATION_1_2",
        "ADD COLUMN downloadArgs"
    ],
    "com/ffmux/app/data/db/DownloadDao.kt": [
        "suspend fun resetForRetry",
        "suspend fun findById"
    ],
    "com/ffmux/app/data/db/DownloadEntity.kt": [
        "STATUS_FAILED",
        "val downloadArgs: String = \"\""
    ],
    "com/ffmux/app/engine/DownloadService.kt": [
        "Graph.appendLog(item.id, line)",
        "parseByteProgress(line)?.let",
        "Graph.clearLog(item.id)",
        "item.downloadArgs, processId, template"
    ],
    "com/ffmux/app/engine/FileSaver.kt": [
        "object FileSaver"
    ],
    "com/ffmux/app/engine/Models.kt": [
        "data class FormatSections",
        "val formatId: String? = null",
        "val sizeBytes: Long? = null"
    ],
    "com/ffmux/app/engine/YtDlpEngine.kt": [
        "fun buildFormatSections",
        "\"--retries\", 10",
        "\"--fragment-retries\", 10",
        "\"--socket-timeout\", 30",
        "\"--merge-output-format\", \"mp4/mkv\"",
        ".getOrNull() ?: \"unknown\"",
        "fun YoutubeDLRequest.applyExtraArgs",
        "extraArgs: String"
    ],
    "com/ffmux/app/ui/AppRoot.kt": [
        "log/{downloadId}",
        "SlidingPillNavBar",
        "indication = null",
        "restoreState = true",
        "tween(150)",
        "isLogRoute"
    ],
    "com/ffmux/app/ui/common/ScreenHeader.kt": [
        "fun ScreenHeader",
        "height(56.dp)"
    ],
    "com/ffmux/app/ui/downloads/DownloadsScreen.kt": [
        "ScreenHeader(",
        "Icons.Outlined.Terminal",
        "Icons.Filled.Refresh",
        "fun ProgressBlock",
        "onRetry = { viewModel.retry(item.id) }",
        "height(8.dp)"
    ],
    "com/ffmux/app/ui/downloads/DownloadsViewModel.kt": [
        "fun retry(id: Long)",
        "resetForRetry(id)"
    ],
    "com/ffmux/app/ui/downloads/LogScreen.kt": [
        "fun LogScreen",
        "FontFamily.Monospace",
        "animateScrollToItem",
        "SelectionContainer",
        "LogBackground",
        "LogTextGreen",
        "statusBarsPadding()",
        "navigationBarsPadding()",
        "Log copied to clipboard"
    ],
    "com/ffmux/app/ui/home/HomeScreen.kt": [
        "ScreenHeader(title = \"Download\")",
        "private fun BestCard",
        "private fun FormatGrid",
        "private fun StickyDownloadBar",
        "heightIn(min = 88.dp)",
        "approx. ",
        "private fun CircularFetchButton",
        "FilledIconButton",
        "Icons.Filled.Close",
        "private fun OptionChips",
        "private fun OptionChip",
        "private fun SubtitleLangDialog",
        "pinnedSubLangs",
        "Icons.Rounded.Subtitles"
    ],
    "com/ffmux/app/ui/home/HomeViewModel.kt": [
        "fun selectedSelector",
        "fun toggleVideo",
        "fun toggleAudio",
        "Intentionally NOT clearing",
        "\"${video.selector}+${audio.selector}\"",
        "fun buildDownloadArgs",
        "var embedThumbnail",
        "var subLangs",
        "--embed-thumbnail",
        "--embed-subs",
        "--sub-langs",
        "--split-chapters"
    ],
    "com/ffmux/app/ui/settings/SettingsScreen.kt": [
        "ScreenHeader(title = \"Settings\")"
    ],
    "com/ffmux/app/ui/settings/SettingsViewModel.kt": [
        "fun checkForUpdate"
    ],
    "com/ffmux/app/ui/theme/Theme.kt": [
        "fun FFMuxTheme"
    ],
    "com/ffmux/app/util/MimeUtils.kt": [
        "object MimeUtils"
    ],
    "com/ffmux/app/util/UrlUtils.kt": [
        "object UrlUtils"
    ]
}

for rel, markers in GATES.items():
    p = "app/src/main/java/" + rel
    if not os.path.isfile(p):
        gate("exists: " + rel, False)
        continue
    src = rd(p)
    missing = [m for m in markers if m not in src]
    gate("content: " + rel, not missing, "missing " + "; ".join(missing))

# The About card must stay gone from Settings.
set_src = rd("app/src/main/java/com/ffmux/app/ui/settings/SettingsScreen.kt")
gate("settings: no About card", 'Text("About' not in set_src)

# Version.
b = rd(BUILD_G)
gate("BUILD: version 1.4.0 / code 7",
     "versionCode = 7" in b and 'versionName = "1.4.0"' in b)

# Manifest untouched: service still declared.
m = rd(MANIFEST)
gate("MANIFEST: DownloadService declared",
     "engine.DownloadService" in m and "MainActivity" in m)

# No stray kotlin files.
known = set(GATES.keys())
strays = []
for root, _, files in os.walk("app/src/main/java"):
    for f in files:
        if f.endswith(".kt"):
            rel = os.path.relpath(os.path.join(root, f), "app/src/main/java")
            if rel not in known:
                strays.append(rel)
gate("tree: no stray .kt files", not strays, ", ".join(strays[:5]))

# kotlin-lite brace/paren balance (strings, chars, comments, templates aware).
def scan(src):
    errs = []
    stack = [("code", 0)]
    depth = 0
    paren = 0
    line = 1
    i = 0
    n = len(src)
    while i < n:
        ch = src[i]
        nxt = src[i + 1] if i + 1 < n else ""
        if ch == "\n":
            line += 1
            i += 1
            continue
        top = stack[-1][0]
        if top == "str":
            if ch == "\\":
                i += 2
                continue
            if ch == '"':
                stack.pop()
            i += 1
            continue
        if top == "char":
            if ch == "\\":
                i += 2
                continue
            if ch == "'":
                stack.pop()
            i += 1
            continue
        if top == "tpl":
            if ch == "{":
                stack[-1] = ("tpl", stack[-1][1] + 1)
            elif ch == "}":
                if stack[-1][1] == 0:
                    stack.pop()
                    depth -= 1
                else:
                    stack[-1] = ("tpl", stack[-1][1] - 1)
            i += 1
            continue
        if ch == "/" and nxt == "/":
            while i < n and src[i] != "\n":
                i += 1
            continue
        if ch == "/" and nxt == "*":
            i += 2
            while i + 1 < n and not (src[i] == "*" and src[i + 1] == "/"):
                if src[i] == "\n":
                    line += 1
                i += 1
            i += 2
            continue
        if ch == '"':
            stack.append(("str", 0))
            i += 1
            continue
        if ch == "'":
            stack.append(("char", 0))
            i += 1
            continue
        if ch == "$" and nxt == "{":
            stack.append(("tpl", 0))
            depth += 1
            i += 2
            continue
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth < 0:
                errs.append("line " + str(line) + ": unbalanced }")
        elif ch == "(":
            paren += 1
        elif ch == ")":
            paren -= 1
            if paren < 0:
                errs.append("line " + str(line) + ": unbalanced )")
        i += 1
    if depth != 0:
        errs.append("final brace depth " + str(depth))
    if paren != 0:
        errs.append("final paren depth " + str(paren))
    if len(stack) != 1 or stack[-1][0] != "code":
        errs.append("unclosed literal: " + str(stack))
    return errs

for rel in sorted(GATES.keys()):
    errs = scan(rd("app/src/main/java/" + rel))
    gate("kotlin-lite brace/paren balance: " + rel, not errs, "; ".join(errs[:3]))

if failed:
    print("GATES FAILED: " + str(failed) + " of " + str(failed + passed))
    sys.exit(1)
print("ALL GATES GREEN (" + str(passed) + " checks)")
PYEOF

echo "== FFMux 1.4.0 installed (patches 1-7, version 1.4.0 / code 7) =="
