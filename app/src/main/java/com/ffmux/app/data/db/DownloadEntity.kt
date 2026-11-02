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
