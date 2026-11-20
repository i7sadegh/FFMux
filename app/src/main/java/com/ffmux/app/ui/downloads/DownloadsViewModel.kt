package com.ffmux.app.ui.downloads

import android.app.Application
import android.net.Uri
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

    fun delete(id: Long, deleteFile: Boolean = false) {
        viewModelScope.launch(Dispatchers.IO) {
            if (deleteFile) {
                // Remove the saved file from storage before dropping
                // the row. Works for both destinations (MediaStore or
                // the SAF folder): both were created by this app, so it
                // holds write access to the Uri it saved.
                val item = Graph.db.downloadDao().findById(id)
                item?.savedUri?.let { uriString ->
                    runCatching {
                        getApplication<Application>()
                            .contentResolver.delete(Uri.parse(uriString), null, null)
                    }
                }
            }
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
