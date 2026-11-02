package com.ffmux.app.ui.downloads

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.ffmux.app.Graph
import com.ffmux.app.engine.DownloadService
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

class DownloadsViewModel(application: Application) : AndroidViewModel(application) {

    val items = Graph.db.downloadDao()
        .observeAll()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    fun cancel(id: Long) {
        DownloadService.cancel(getApplication(), id)
    }

    fun delete(id: Long) {
        viewModelScope.launch(Dispatchers.IO) {
            Graph.db.downloadDao().delete(id)
        }
    }

    /** Puts a failed or canceled download back into the queue. */
    fun retry(id: Long) {
        viewModelScope.launch(Dispatchers.IO) {
            Graph.clearLog(id)
            val requeued = Graph.db.downloadDao().resetForRetry(id)
            if (requeued > 0) {
                DownloadService.start(getApplication())
            }
        }
    }
}
