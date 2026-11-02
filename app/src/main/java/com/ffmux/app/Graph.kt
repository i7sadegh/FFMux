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
