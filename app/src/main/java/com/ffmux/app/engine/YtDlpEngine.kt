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
                val videoBytes = estimatedBytes(sample, info.duration)
                val audioBytes =
                    if (sample == null || sample.acodec.isNullOrEmpty() || sample.acodec == "none") {
                        estimatedBytes(bestAudio, info.duration)
                    } else {
                        null
                    }
                FormatOption(
                    label = "${h}p",
                    selector = "bestvideo[height<=$h]+bestaudio/best[height<=$h]",
                    kind = FormatKind.VIDEO,
                    ext = sample?.ext?.uppercase(),
                    fps = sample?.fps?.toInt(),
                    size = sizeText(addSizes(videoBytes, audioBytes))
                )
            }

            val audio = audioFormats.mapNotNull { it.ext }.distinct().sorted().map { e ->
                val sample = audioFormats.filter { it.ext == e }.maxByOrNull { it.tbr ?: 0.0 }
                FormatOption(
                    label = e.uppercase(),
                    selector = "bestaudio[ext=$e]/bestaudio",
                    kind = FormatKind.AUDIO,
                    ext = e.uppercase(),
                    kbps = sample?.tbr?.toInt(),
                    size = sizeText(estimatedBytes(sample, info.duration))
                )
            }
            val audioOptions = if (audio.isEmpty()) {
                listOf(FormatOption("Audio only", "bestaudio[ext=m4a]/bestaudio", FormatKind.AUDIO))
            } else {
                audio
            }

            val best = FormatOption(
                label = "Best",
                selector = "bestvideo*+bestaudio/best",
                kind = FormatKind.VIDEO,
                note = "Best video + audio"
            )
            return listOf(best) + video + audioOptions
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
