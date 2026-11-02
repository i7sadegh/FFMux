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
            // YouTube likes to reset long transfers (errno 104):
            // retry every file and every fragment before giving up.
            addOption("--retries", 10)
            addOption("--fragment-retries", 10)
            addOption("--socket-timeout", 30)
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

        /** Builds the format catalog shown on the Home screen: every
         * stream as its own card, videos and audios listed apart. */
        fun buildFormatOptions(info: VideoInfo): FormatCatalog {
            val duration = info.duration
            val audioFormats = info.formats.filter {
                (it.vcodec == null || it.vcodec == "none") &&
                    !it.acodec.isNullOrEmpty() && it.acodec != "none"
            }.distinctBy { it.formatId }
            val videoFormats = info.formats.filter {
                !it.vcodec.isNullOrEmpty() && it.vcodec != "none"
            }.distinctBy { it.formatId }

            val audio = audioFormats
                .sortedWith(compareByDescending { it.tbr ?: 0.0 })
                .map { f ->
                    val bytes = estimatedBytes(f, duration)
                    FormatOption(
                        id = f.formatId ?: "bestaudio",
                        label = f.tbr?.toInt()?.let { "$it kbps" }
                            ?: f.ext?.uppercase() ?: "Audio",
                        selector = f.formatId ?: "bestaudio",
                        kind = FormatKind.AUDIO,
                        ext = f.ext?.uppercase(),
                        kbps = f.tbr?.toInt(),
                        size = sizeText(bytes, estimated = f.filesize == null),
                        sizeBytes = bytes
                    )
                }
            val audioOptions = if (audio.isEmpty()) {
                listOf(
                    FormatOption(
                        id = "bestaudio",
                        label = "Audio only",
                        selector = "bestaudio/best",
                        kind = FormatKind.AUDIO
                    )
                )
            } else {
                audio
            }

            val video = videoFormats
                .sortedWith(
                    compareByDescending<VideoFormat> { it.height ?: 0 }
                        .thenByDescending { it.tbr ?: 0.0 }
                )
                .map { f ->
                    val bytes = estimatedBytes(f, duration)
                    FormatOption(
                        id = f.formatId ?: "bestvideo",
                        label = f.height?.let { "${it}p" }
                            ?: f.ext?.uppercase() ?: "Video",
                        selector = f.formatId ?: "bestvideo",
                        kind = FormatKind.VIDEO,
                        ext = f.ext?.uppercase(),
                        width = f.width,
                        height = f.height,
                        fps = f.fps?.toInt(),
                        kbps = f.tbr?.toInt(),
                        size = sizeText(bytes, estimated = f.filesize == null),
                        sizeBytes = bytes,
                        hasAudio = !f.acodec.isNullOrEmpty() && f.acodec != "none"
                    )
                }

            val bestVideoOnly = videoFormats
                .filter { it.acodec.isNullOrEmpty() || it.acodec == "none" }
                .maxWithOrNull(compareBy({ it.height ?: 0 }, { it.tbr ?: 0.0 }))
            val bestAudioBytes =
                audioFormats.maxByOrNull { it.tbr ?: 0.0 }?.let { estimatedBytes(it, duration) }
            val bestBytes = addSizes(
                bestVideoOnly?.let { estimatedBytes(it, duration) },
                bestAudioBytes
            )
            val best = FormatOption(
                id = "best",
                label = "Best",
                selector = "bestvideo*+bestaudio/best",
                kind = FormatKind.VIDEO,
                note = "Best video + best audio, merged",
                size = sizeText(bestBytes, estimated = true),
                sizeBytes = bestBytes,
                hasAudio = true,
                isBest = true
            )
            return FormatCatalog(best = best, video = video, audio = audioOptions)
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

        private fun sizeText(bytes: Long?, estimated: Boolean): String? {
            if (bytes == null) return null
            val mb = bytes / 1048576.0
            val text = when {
                mb >= 1024.0 -> String.format("%.1f GB", mb / 1024.0)
                mb >= 100.0 -> String.format("%.0f MB", mb)
                mb >= 1.0 -> String.format("%.1f MB", mb)
                else -> String.format("%.0f KB", bytes / 1024.0)
            }
            return if (estimated) "\u2248 $text" else text
        }
    }
}
