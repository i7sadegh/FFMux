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
    val width: Int? = null,
    val height: Int? = null,
    val fps: Double? = null,
    val vcodec: String? = null,
    val acodec: String? = null,
    val filesize: Long? = null,
    val tbr: Double? = null
)

enum class FormatKind { VIDEO, AUDIO }

data class FormatOption(
    val id: String,
    val label: String,
    val selector: String,
    val kind: FormatKind,
    val ext: String? = null,
    val width: Int? = null,
    val height: Int? = null,
    val fps: Int? = null,
    val kbps: Int? = null,
    val size: String? = null,
    val sizeBytes: Long? = null,
    val note: String? = null,
    val hasAudio: Boolean = false,
    val isBest: Boolean = false
)

data class FormatCatalog(
    val best: FormatOption,
    val video: List<FormatOption>,
    val audio: List<FormatOption>
)
