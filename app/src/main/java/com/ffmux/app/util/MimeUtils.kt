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
