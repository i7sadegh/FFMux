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
import com.ffmux.app.engine.FormatOption
import com.ffmux.app.engine.VideoInfo
import com.ffmux.app.engine.YtDlpEngine
import kotlinx.coroutines.launch

sealed interface HomeUiState {
    data object Idle : HomeUiState
    data object Loading : HomeUiState
    data class Error(val message: String) : HomeUiState
    data class Info(val info: VideoInfo, val options: List<FormatOption>) : HomeUiState
}

class HomeViewModel(application: Application) : AndroidViewModel(application) {

    var url by mutableStateOf("")
        private set
    var state by mutableStateOf<HomeUiState>(HomeUiState.Idle)
        private set
    var selectedFormat by mutableStateOf(-1)

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
                val options = YtDlpEngine.buildFormatOptions(info)
                if (options.isEmpty()) {
                    state = HomeUiState.Error("No downloadable formats found.")
                    return@launch
                }
                selectedFormat = 0
                state = HomeUiState.Info(info, options)
            } catch (e: Exception) {
                state = HomeUiState.Error((e.message ?: "Could not fetch video info.").take(300))
            }
        }
    }

    fun startDownload(onQueued: () -> Unit) {
        val current = state as? HomeUiState.Info ?: return
        if (selectedFormat !in current.options.indices) return
        val option = current.options[selectedFormat]
        val info = current.info
        val target = url.trim()

        viewModelScope.launch {
            val entity = DownloadEntity(
                url = target,
                title = info.title ?: "Untitled",
                thumbnail = info.thumbnail,
                uploader = info.uploader,
                durationSec = info.duration,
                formatSelector = option.selector,
                formatLabel = option.label,
                createdAt = System.currentTimeMillis()
            )
            Graph.db.downloadDao().insert(entity)
            DownloadService.start(getApplication())
            state = HomeUiState.Idle
            url = ""
            selectedFormat = -1
            onQueued()
        }
    }
}
