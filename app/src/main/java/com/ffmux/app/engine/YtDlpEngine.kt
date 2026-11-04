package com.ffmux.app.engine

import android.content.Context
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLRequest
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

/**
 * Thin wrapper around the youtubedl-android library.
 * All public functions either suspend onto Dispatchers.IO or must be called from IO.
 */
class YtDlpEngine(private val appContext: Context) {

    private val json = Json {
        ignoreUnknownKeys = true
        isLenient = true
    }

    /**
     * Fetches metadata for a single video (equivalent of `yt-dlp -J`).
     * A certificate verification failure triggers one retry after the
     * CA bundle of the bundled Python has been refreshed, so a stale
     * root store never blocks a site for good.
     */
    suspend fun fetchInfo(url: String): VideoInfo = withContext(Dispatchers.IO) {
        try {
            executeInfo(url)
        } catch (e: Exception) {
            if (isCertificateError(e.message) && CaBundleFixer.refresh(appContext)) {
                executeInfo(url)
            } else {
                throw e
            }
        }
    }

    private fun executeInfo(url: String): VideoInfo {
        val request = YoutubeDLRequest(url).apply {
            addOption("-J")
            addOption("--no-playlist")
            addOption("--retries", 10)
            addOption("--socket-timeout", 30)
        }
        val response = YoutubeDL.getInstance().execute(request)
        return json.decodeFromString(response.out)
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
        try {
            executeDownload(url, selector, extraArgs, processId, outputTemplate, onProgress)
        } catch (e: Exception) {
            // Same safety net as fetchInfo: refresh the CA bundle once
            // and run the request again, so one stale certificate list
            // cannot kill an otherwise healthy download.
            if (isCertificateError(e.message) && CaBundleFixer.refresh(appContext)) {
                executeDownload(url, selector, extraArgs, processId, outputTemplate, onProgress)
            } else {
                throw e
            }
        }
    }

    private fun executeDownload(
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

    /** True when a failure message is an HTTPS certificate problem. */
    private fun isCertificateError(message: String?): Boolean =
        message?.contains("CERTIFICATE_VERIFY_FAILED") == true ||
            message?.contains("certificate verify failed") == true

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

/**
 * Replaces the CA certificate bundle the bundled Python verifies HTTPS
 * connections with. youtubedl-android ships a snapshot of the Mozilla
 * root store; once it ages, yt-dlp rejects sites whose certificates
 * were issued by newer authorities with
 * "unable to get local issuer certificate". The bundle lives in
 * writable app storage, so the current list can simply be downloaded
 * over it (the download itself uses the healthy Android system trust
 * store, not the stale file).
 */
internal object CaBundleFixer {

    /** Refresh the bundle when the shipped one is older than this. */
    private const val STALE_AFTER_MS = 30L * 24 * 60 * 60 * 1000L

    /** Mirror of https://curl.se/ca/cacert.pem on GitHub, as a fallback. */
    private val SOURCES = listOf(
        "https://curl.se/ca/cacert.pem",
        "https://raw.githubusercontent.com/curl/curl-www/ca/cacert.pem"
    )

    /** The exact file youtubedl-android points SSL_CERT_FILE at. */
    fun certFile(context: Context): File =
        File(
            File(context.noBackupFilesDir, "youtubedl-android"),
            "packages/python/usr/etc/tls/cert.pem"
        )

    /** Refreshes the bundle when it is missing or older than 30 days. */
    fun refreshIfStale(context: Context) {
        val target = certFile(context)
        if (target.exists() &&
            System.currentTimeMillis() - target.lastModified() < STALE_AFTER_MS
        ) {
            return
        }
        refresh(context)
    }

    /** Downloads the current Mozilla CA list into the engine's cert path. */
    fun refresh(context: Context): Boolean {
        val target = certFile(context)
        val dir = target.parentFile ?: return false
        if (!dir.exists() && !dir.mkdirs()) return false
        val tmp = File(dir, "cert.pem.tmp")
        try {
            for (url in SOURCES) {
                if (downloadTo(url, tmp) && isPemBundle(tmp)) {
                    if (tmp.renameTo(target)) return true
                    // Some filesystems refuse the rename; copy instead.
                    try {
                        tmp.copyTo(target, overwrite = true)
                        tmp.delete()
                        return true
                    } catch (e: Exception) {
                        // try the next source
                    }
                }
                tmp.delete()
            }
        } catch (e: Exception) {
            runCatching { tmp.delete() }
            return false
        }
        return false
    }

    private fun downloadTo(url: String, target: File): Boolean {
        return try {
            val connection = URL(url).openConnection() as HttpURLConnection
            connection.connectTimeout = 15000
            connection.readTimeout = 30000
            connection.instanceFollowRedirects = true
            if (connection.responseCode != 200) {
                connection.disconnect()
                return false
            }
            connection.inputStream.use { input ->
                target.outputStream().use { output -> input.copyTo(output) }
            }
            connection.disconnect()
            target.length() > 100_000
        } catch (e: Exception) {
            runCatching { target.delete() }
            false
        }
    }

    private fun isPemBundle(file: File): Boolean = try {
        file.readText().contains("-----BEGIN CERTIFICATE-----")
    } catch (e: Exception) {
        false
    }
}
