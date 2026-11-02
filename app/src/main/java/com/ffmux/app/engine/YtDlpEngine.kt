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
        }
        val response = YoutubeDL.getInstance().execute(request)
        json.decodeFromString(response.out)
    }

    /**
     * Blocking download call. Runs yt-dlp with the chosen format selector and
     * reports progress through [onProgress]. Must be called from an IO dispatcher.
     */
    fun download(
        url: String,
        selector: String,
        processId: String,
        outputTemplate: String,
        onProgress: (Float, Long, String) -> Unit
    ) {
        val request = YoutubeDLRequest(url).apply {
            addOption("--no-playlist")
            addOption("-f", selector)
            addOption("-o", outputTemplate)
            addOption("--no-mtime")
        }
        YoutubeDL.getInstance().execute(request, processId) { progress, eta, line ->
            onProgress(progress, eta, line)
        }
    }

    suspend fun currentVersion(): String = withContext(Dispatchers.IO) {
        runCatching { YoutubeDL.getInstance().version(appContext) }.getOrNull() ?: "unknown"
    }

    /**
     * Replaces the bundled yt-dlp binary with the latest stable release from
     * the official yt-dlp GitHub releases — no app update required.
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

        /** Builds the quality options shown on the Home screen. */
        fun buildFormatOptions(info: VideoInfo): List<FormatOption> {
            val heights = info.formats
                .filter { !it.vcodec.isNullOrEmpty() && it.vcodec != "none" && it.height != null }
                .map { it.height!! }
                .distinct()
                .sortedDescending()

            val video = if (heights.isEmpty()) {
                listOf(FormatOption("Best available", "bestvideo+bestaudio/best", FormatKind.VIDEO))
            } else {
                heights.map { h ->
                    FormatOption(
                        label = "${h}p",
                        selector = "bestvideo[height<=$h]+bestaudio/best[height<=$h]",
                        kind = FormatKind.VIDEO
                    )
                }
            }
            return video + FormatOption("Audio only", "bestaudio[ext=m4a]/bestaudio", FormatKind.AUDIO)
        }
    }
}
