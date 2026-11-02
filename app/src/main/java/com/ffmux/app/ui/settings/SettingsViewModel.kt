package com.ffmux.app.ui.settings

import android.app.Application
import android.content.Intent
import android.net.Uri
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.ffmux.app.Graph
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

class SettingsViewModel(application: Application) : AndroidViewModel(application) {

    val treeUri = Graph.settings.treeUri
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), null)

    var engineVersion by mutableStateOf<String?>(null)
        private set
    var updating by mutableStateOf(false)
        private set
    var updateMessage by mutableStateOf<String?>(null)
        private set

    init {
        viewModelScope.launch {
            runCatching { Graph.awaitEngine() }
            engineVersion = Graph.engine.currentVersion()
        }
    }

    fun chooseFolder(uri: Uri) {
        val app = getApplication<Application>()
        runCatching {
            app.contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            )
        }
        viewModelScope.launch {
            Graph.settings.setTreeUri(uri.toString())
        }
    }

    fun resetFolder() {
        viewModelScope.launch {
            Graph.settings.setTreeUri(null)
        }
    }

    fun checkForUpdate() {
        if (updating) return
        updating = true
        updateMessage = null
        viewModelScope.launch {
            try {
                Graph.awaitEngine()
                updateMessage = Graph.engine.update()
                engineVersion = Graph.engine.currentVersion()
            } catch (e: Exception) {
                updateMessage = "Update failed: ${(e.message ?: "unknown error").take(200)}"
            } finally {
                updating = false
            }
        }
    }
}
