package com.ffmux.app.ui.downloads

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.OpenInNew
import androidx.compose.material3.Card
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.ffmux.app.data.db.DownloadEntity

@Composable
fun DownloadsScreen(viewModel: DownloadsViewModel = viewModel()) {
    val items by viewModel.items.collectAsStateWithLifecycle()
    val context = LocalContext.current

    if (items.isEmpty()) {
        Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Text(
                "No downloads yet.\nShare a link from any app,\nor paste one on the Home tab.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center
            )
        }
        return
    }

    LazyColumn(
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        items(items, key = { it.id }) { item ->
            DownloadItemCard(
                item = item,
                onCancel = { viewModel.cancel(item.id) },
                onDelete = { viewModel.delete(item.id) },
                onOpen = {
                    item.savedUri?.let { openSavedFile(context, it) }
                }
            )
        }
    }
}

@Composable
private fun DownloadItemCard(
    item: DownloadEntity,
    onCancel: () -> Unit,
    onDelete: () -> Unit,
    onOpen: () -> Unit
) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            Text(
                item.title,
                style = MaterialTheme.typography.titleSmall,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            Text(
                "${item.formatLabel} • ${statusText(item)}",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            when (item.status) {
                DownloadEntity.STATUS_RUNNING -> {
                    LinearProgressIndicator(
                        progress = { (item.progress / 100f).coerceIn(0f, 1f) },
                        modifier = Modifier.fillMaxWidth()
                    )
                }
                DownloadEntity.STATUS_SAVING -> {
                    LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
                }
                else -> {}
            }
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.End,
                verticalAlignment = Alignment.CenterVertically
            ) {
                if (item.status == DownloadEntity.STATUS_QUEUED ||
                    item.status == DownloadEntity.STATUS_RUNNING ||
                    item.status == DownloadEntity.STATUS_SAVING
                ) {
                    IconButton(onClick = onCancel) {
                        Icon(Icons.Filled.Close, contentDescription = "Cancel")
                    }
                }
                if (item.status == DownloadEntity.STATUS_COMPLETED) {
                    IconButton(onClick = onOpen) {
                        Icon(Icons.Outlined.OpenInNew, contentDescription = "Open")
                    }
                }
                IconButton(onClick = onDelete) {
                    Icon(Icons.Outlined.Delete, contentDescription = "Delete")
                }
            }
        }
    }
}

private fun statusText(item: DownloadEntity): String = when (item.status) {
    DownloadEntity.STATUS_QUEUED -> "Queued"
    DownloadEntity.STATUS_RUNNING ->
        if (item.progress > 0f) "${item.progress.toInt()}%" else "Starting…"
    DownloadEntity.STATUS_SAVING -> "Saving…"
    DownloadEntity.STATUS_COMPLETED -> "Completed"
    DownloadEntity.STATUS_CANCELED -> "Canceled"
    DownloadEntity.STATUS_FAILED -> item.error?.let { "Failed — ${it.take(80)}" } ?: "Failed"
    else -> item.status
}

private fun openSavedFile(context: Context, uriString: String) {
    val uri = Uri.parse(uriString)
    val intent = Intent(Intent.ACTION_VIEW).apply {
        setDataAndType(uri, "*/*")
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }
    runCatching { context.startActivity(intent) }
}
