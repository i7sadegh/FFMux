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

    /** Puts a failed download back into the queue with the same link
     *  and the same format selector. */
    fun retry(id: Long) {
        viewModelScope.launch(Dispatchers.IO) {
            Graph.db.downloadDao().requeue(id)
            DownloadService.start(getApplication())
        }
    }

    fun delete(id: Long) {
        viewModelScope.launch(Dispatchers.IO) {
            Graph.db.downloadDao().delete(id)
        }
    }
}
