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
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.OpenInNew
import androidx.compose.material.icons.outlined.Terminal
import androidx.compose.material3.Card
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.ffmux.app.Graph
import com.ffmux.app.data.db.DownloadEntity
import com.ffmux.app.ui.common.ScreenHeader

@Composable
fun DownloadsScreen(
    onOpenLog: (Long) -> Unit,
    viewModel: DownloadsViewModel = viewModel()
) {
    val items by viewModel.items.collectAsStateWithLifecycle()
    val logs by Graph.downloadLogs.collectAsState()
    val liveBytes by Graph.byteProgress.collectAsState()
    val context = LocalContext.current

    Column(modifier = Modifier.fillMaxSize()) {
        ScreenHeader(
            title = "Downloads",
            actions = {
                // Terminal log button, pinned to the far right end of the row.
                if (items.isNotEmpty()) {
                    IconButton(onClick = {
                        items.firstOrNull()?.let { onOpenLog(it.id) }
                    }) {
                        Icon(
                            Icons.Outlined.Terminal,
                            contentDescription = "Terminal log"
                        )
                    }
                }
            }
        )

        if (items.isEmpty()) {
            Box(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth(),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    "No downloads yet.\nShare a link from any app,\nor paste one on the Home tab.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center
                )
            }
        } else {
            LazyColumn(
                modifier = Modifier.weight(1f),
                contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 4.dp, bottom = 16.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                items(items, key = { it.id }) { item ->
                    DownloadItemCard(
                        item = item,
                        liveBytes = liveBytes[item.id],
                        hasLog = !logs[item.id].orEmpty().isEmpty(),
                        onCancel = { viewModel.cancel(item.id) },
                        onDelete = { viewModel.delete(item.id) },
                        onOpen = {
                            item.savedUri?.let { openSavedFile(context, it) }
                        },
                        onRetry = { viewModel.retry(item.id) },
                        onOpenLog = { onOpenLog(item.id) }
                    )
                }
            }
        }
    }
}

@Composable
private fun DownloadItemCard(
    item: DownloadEntity,
    liveBytes: Graph.ByteProgress?,
    hasLog: Boolean,
    onCancel: () -> Unit,
    onDelete: () -> Unit,
    onOpen: () -> Unit,
    onRetry: () -> Unit,
    onOpenLog: () -> Unit
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
                "${item.formatLabel} \u00B7 ${statusText(item)}",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            when (item.status) {
                DownloadEntity.STATUS_QUEUED,
                DownloadEntity.STATUS_RUNNING,
                DownloadEntity.STATUS_SAVING -> ProgressBlock(item, liveBytes)
                else -> {}
            }
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.End,
                verticalAlignment = Alignment.CenterVertically
            ) {
                if (item.status == DownloadEntity.STATUS_FAILED ||
                    item.status == DownloadEntity.STATUS_CANCELED
                ) {
                    IconButton(onClick = onRetry) {
                        Icon(Icons.Filled.Refresh, contentDescription = "Retry")
                    }
                }
                if (hasLog) {
                    IconButton(onClick = onOpenLog) {
                        Icon(Icons.Outlined.Terminal, contentDescription = "Terminal log")
                    }
                }
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

/**
 * F-Droid style progress: a fat determinate bar plus one status line with
 * percentage and downloaded/total bytes. The bar keeps the exact same
 * height in every state (waiting, starting, downloading, saving) so the
 * card never jumps when the download starts.
 */
@Composable
private fun ProgressBlock(item: DownloadEntity, liveBytes: Graph.ByteProgress?) {
    val determinate = item.status == DownloadEntity.STATUS_RUNNING && item.progress > 0f
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        if (determinate) {
            LinearProgressIndicator(
                progress = { (item.progress / 100f).coerceIn(0f, 1f) },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(8.dp)
            )
        } else {
            LinearProgressIndicator(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(8.dp)
            )
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                text = progressLabel(item, liveBytes),
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f)
            )
            if (determinate) {
                item.etaSec?.takeIf { it > 0 }?.let { eta ->
                    Text(
                        text = "ETA ${formatEta(eta)}",
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }
    }
}

private fun progressLabel(item: DownloadEntity, live: Graph.ByteProgress?): String =
    when (item.status) {
        DownloadEntity.STATUS_QUEUED -> "Waiting in queue..."
        DownloadEntity.STATUS_RUNNING -> when {
            item.progress <= 0f -> "Starting..."
            live != null && live.total > 0 ->
                "${item.progress.toInt()}% \u00B7 ${byteText(live.downloaded)} / ${byteText(live.total)}"
            else -> "${item.progress.toInt()}%"
        }
        DownloadEntity.STATUS_SAVING -> "Saving file..."
        else -> ""
    }

private fun byteText(bytes: Long): String {
    val mb = bytes / 1048576.0
    return when {
        mb >= 1024.0 -> String.format("%.2f GB", mb / 1024.0)
        mb >= 10.0 -> String.format("%.1f MB", mb)
        mb >= 0.01 -> String.format("%.1f MB", mb)
        else -> String.format("%.0f KB", bytes / 1024.0)
    }
}

private fun formatEta(seconds: Long): String {
    val h = seconds / 3600
    val m = (seconds % 3600) / 60
    val s = seconds % 60
    return if (h > 0) {
        String.format("%d:%02d:%02d", h, m, s)
    } else {
        String.format("%d:%02d", m, s)
    }
}

private fun statusText(item: DownloadEntity): String = when (item.status) {
    DownloadEntity.STATUS_QUEUED -> "Queued"
    DownloadEntity.STATUS_RUNNING -> "Downloading"
    DownloadEntity.STATUS_SAVING -> "Saving"
    DownloadEntity.STATUS_COMPLETED -> "Completed"
    DownloadEntity.STATUS_CANCELED -> "Canceled"
    DownloadEntity.STATUS_FAILED -> item.error?.let { "Failed \u2014 ${it.take(60)}" } ?: "Failed"
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
