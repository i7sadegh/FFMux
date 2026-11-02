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
