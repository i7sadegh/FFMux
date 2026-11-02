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
import com.ffmux.app.engine.FormatCatalog
import com.ffmux.app.engine.FormatOption
import com.ffmux.app.engine.VideoInfo
import com.ffmux.app.engine.YtDlpEngine
import kotlinx.coroutines.launch

sealed interface HomeUiState {
    data object Idle : HomeUiState
    data object Loading : HomeUiState
    data class Error(val message: String) : HomeUiState
    data class Info(val info: VideoInfo, val catalog: FormatCatalog) : HomeUiState
}

class HomeViewModel(application: Application) : AndroidViewModel(application) {

    var url by mutableStateOf("")
        private set
    var state by mutableStateOf<HomeUiState>(HomeUiState.Idle)
        private set
    var selectedVideoId by mutableStateOf<String?>(null)
    var selectedAudioId by mutableStateOf<String?>(null)
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
                val catalog = YtDlpEngine.buildFormatOptions(info)
                if (catalog.video.isEmpty() && catalog.audio.isEmpty()) {
                    state = HomeUiState.Error("No downloadable formats found.")
                    return@launch
                }
                selectedVideoId = null
                selectedAudioId = null
                editableTitle = info.title ?: "Untitled"
                editableUploader = info.uploader ?: ""
                state = HomeUiState.Info(info, catalog)
            } catch (e: Exception) {
                state = HomeUiState.Error((e.message ?: "Could not fetch video info.").take(300))
            }
        }
    }

    fun toggleVideo(option: FormatOption) {
        selectedVideoId = if (selectedVideoId == option.id) null else option.id
    }

    fun toggleAudio(option: FormatOption) {
        selectedAudioId = if (selectedAudioId == option.id) null else option.id
    }

    fun selectBest() {
        selectedVideoId = null
        selectedAudioId = null
    }

    /** The yt-dlp format selector for the current card selection. */
    fun resolveSelector(catalog: FormatCatalog): String {
        val video = catalog.video.firstOrNull { it.id == selectedVideoId }
        val audio = catalog.audio.firstOrNull { it.id == selectedAudioId }
        return when {
            video == null && audio == null -> catalog.best.selector
            video == null -> audio!!.selector
            video.hasAudio -> video.selector
            else -> video.selector + "+" + (audio?.selector ?: "bestaudio/best")
        }
    }

    /** Short label of the current selection, stored with the download. */
    fun resolveLabel(catalog: FormatCatalog): String {
        val video = catalog.video.firstOrNull { it.id == selectedVideoId }
        val audio = catalog.audio.firstOrNull { it.id == selectedAudioId }
        return when {
            video == null && audio == null -> "Best"
            video == null -> "Audio " + (audio?.label ?: "")
            video.hasAudio -> video.label + " (" + video.id + ")"
            else -> video.label + " (" + video.id + "+" +
                (audio?.id ?: "best audio") + ")"
        }
    }

    /** Estimated size of the file the current selection produces. */
    fun resolveSizeBytes(catalog: FormatCatalog): Long? {
        val video = catalog.video.firstOrNull { it.id == selectedVideoId }
        val audio = catalog.audio.firstOrNull { it.id == selectedAudioId }
        val fallbackAudioBytes = catalog.audio.firstOrNull()?.sizeBytes
        return when {
            video == null && audio == null -> catalog.best.sizeBytes
            video == null -> audio?.sizeBytes
            video.hasAudio -> video.sizeBytes
            else -> sumBytes(video.sizeBytes, audio?.sizeBytes ?: fallbackAudioBytes)
        }
    }

    private fun sumBytes(a: Long?, b: Long?): Long? =
        if (a != null && b != null) a + b else (a ?: b)

    fun startDownload(onQueued: () -> Unit) {
        val current = state as? HomeUiState.Info ?: return
        val selector = resolveSelector(current.catalog)
        val label = resolveLabel(current.catalog)
        val info = current.info
        val target = url.trim()

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
            state = HomeUiState.Idle
            url = ""
            selectedVideoId = null
            selectedAudioId = null
            onQueued()
        }
    }
}
