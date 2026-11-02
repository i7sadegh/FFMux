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

    fun initialize(context: Context) {
        val app = context.applicationContext
        db = Room.databaseBuilder(app, AppDatabase::class.java, "ffmux.db").build()
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
