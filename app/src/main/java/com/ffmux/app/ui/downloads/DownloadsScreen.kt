package com.ffmux.app.ui.downloads

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Terminal
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.OpenInNew
import androidx.compose.material3.Card
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.ffmux.app.data.db.DownloadEntity

@Composable
fun DownloadsScreen(viewModel: DownloadsViewModel = viewModel()) {
    val items by viewModel.items.collectAsStateWithLifecycle()
    val context = LocalContext.current
    var showTerminal by remember { mutableStateOf(false) }

    Column(modifier = Modifier.fillMaxSize()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(start = 16.dp, end = 4.dp, top = 12.dp, bottom = 4.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text("Downloads", style = MaterialTheme.typography.headlineSmall)
            IconButton(onClick = { showTerminal = true }) {
                Icon(
                    Icons.Filled.Terminal,
                    contentDescription = "Terminal log",
                    modifier = Modifier.size(20.dp),
                    tint = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
        if (items.isEmpty()) {
            Box(modifier = Modifier.weight(1f), contentAlignment = Alignment.Center) {
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
                contentPadding = PaddingValues(
                    start = 16.dp, end = 16.dp, top = 4.dp, bottom = 16.dp
                ),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                items(items, key = { it.id }) { item ->
                    DownloadItemCard(
                        item = item,
                        onCancel = { viewModel.cancel(item.id) },
                        onDelete = { viewModel.delete(item.id) },
                        onOpen = {
                            item.savedUri?.let { openSavedFile(context, it) }
                        },
                        onRetry = { viewModel.retry(item.id) }
                    )
                }
            }
        }
    }
    if (showTerminal) {
        TerminalDialog(items = items, onDismiss = { showTerminal = false })
    }
}

@Composable
private fun DownloadItemCard(
    item: DownloadEntity,
    onCancel: () -> Unit,
    onDelete: () -> Unit,
    onOpen: () -> Unit,
    onRetry: () -> Unit
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
                DownloadEntity.STATUS_QUEUED ->
                    DownloadProgressBlock(item = item, indeterminate = false, onCancel = onCancel)
                DownloadEntity.STATUS_RUNNING ->
                    DownloadProgressBlock(item = item, indeterminate = false, onCancel = onCancel)
                DownloadEntity.STATUS_SAVING ->
                    DownloadProgressBlock(item = item, indeterminate = true, onCancel = null)
                else -> {}
            }
            if (item.status == DownloadEntity.STATUS_FAILED) {
                item.error?.let { err ->
                    Text(
                        err,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.error,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis
                    )
                }
            }
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.End,
                verticalAlignment = Alignment.CenterVertically
            ) {
                if (item.status == DownloadEntity.STATUS_FAILED) {
                    IconButton(onClick = onRetry) {
                        Icon(Icons.Filled.Refresh, contentDescription = "Retry")
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

/** The F-Droid style row: "4.9 MiB / 9.6 MiB" on the left, "51%" on the
 *  right, the bar below and the grey cancel button on the right. */
@Composable
private fun DownloadProgressBlock(
    item: DownloadEntity,
    indeterminate: Boolean,
    onCancel: (() -> Unit)?
) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    progressLeftText(item, indeterminate),
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Spacer(Modifier.weight(1f))
                Text(
                    progressRightText(item, indeterminate),
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            FdroidProgressBar(
                progress = (item.progress / 100f).coerceIn(0f, 1f),
                indeterminate = indeterminate
            )
        }
        if (onCancel != null) {
            IconButton(onClick = onCancel) {
                Icon(
                    Icons.Filled.Close,
                    contentDescription = "Cancel",
                    tint = Color(0xFF9E9E9E),
                    modifier = Modifier.size(22.dp)
                )
            }
        }
    }
}

/** The F-Droid download bar: a dark-blue fill on a green track with a
 *  blue dot at the end of the bar. */
@Composable
private fun FdroidProgressBar(progress: Float, indeterminate: Boolean) {
    val fill = Color(0xFF015198)
    val track = Color(0xFF96BC19)
    val sweep = rememberInfiniteTransition(label = "fdroidSweep")
    val sweepPos by sweep.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(tween(1400, easing = LinearEasing)),
        label = "fdroidSweepPos"
    )
    Canvas(modifier = Modifier.fillMaxWidth().height(12.dp)) {
        val barHeight = 5.dp.toPx()
        val radius = barHeight / 2f
        val cy = size.height / 2f
        val dotRadius = 4.dp.toPx()
        val trackRight = size.width - dotRadius
        if (indeterminate) {
            drawRoundRect(
                color = track,
                topLeft = Offset(0f, cy - radius),
                size = Size(trackRight, barHeight),
                cornerRadius = CornerRadius(radius, radius)
            )
            drawCircle(
                color = fill,
                radius = dotRadius,
                center = Offset(sweepPos * trackRight, cy)
            )
        } else {
            val fillWidth = (trackRight * progress).coerceIn(0f, trackRight)
            if (fillWidth > 0f) {
                drawRoundRect(
                    color = fill,
                    topLeft = Offset(0f, cy - radius),
                    size = Size(fillWidth, barHeight),
                    cornerRadius = CornerRadius(radius, radius)
                )
            }
            val gap = 6.dp.toPx()
            val greenStart = fillWidth + gap
            if (greenStart < trackRight) {
                drawRoundRect(
                    color = track,
                    topLeft = Offset(greenStart, cy - radius),
                    size = Size(trackRight - greenStart, barHeight),
                    cornerRadius = CornerRadius(radius, radius)
                )
            }
            drawCircle(
                color = fill,
                radius = dotRadius,
                center = Offset(trackRight, cy)
            )
        }
    }
}

private fun progressLeftText(item: DownloadEntity, indeterminate: Boolean): String = when {
    item.status == DownloadEntity.STATUS_QUEUED -> "Queued"
    indeterminate -> "Saving…"
    item.downloadedBytes != null && item.totalBytes != null ->
        formatBytes(item.downloadedBytes) + " / " + formatBytes(item.totalBytes)
    else -> "Downloading…"
}

private fun progressRightText(item: DownloadEntity, indeterminate: Boolean): String = when {
    item.status == DownloadEntity.STATUS_QUEUED -> ""
    indeterminate -> ""
    item.progress > 0f -> item.progress.toInt().toString() + "%"
    else -> ""
}

/** 4.9 MiB / 9.6 MiB style, like the F-Droid download row. */
private fun formatBytes(bytes: Long): String {
    val kib = bytes / 1024.0
    val mib = kib / 1024.0
    val gib = mib / 1024.0
    return when {
        gib >= 1.0 -> String.format("%.1f GiB", gib)
        mib >= 10.0 -> String.format("%.0f MiB", mib)
        mib >= 1.0 -> String.format("%.1f MiB", mib)
        kib >= 1.0 -> String.format("%.0f KiB", kib)
        else -> bytes.toString() + " B"
    }
}

/** Full-screen terminal: the yt-dlp command and the output of every
 *  download, colored like a terminal. */
@Composable
private fun TerminalDialog(
    items: List<DownloadEntity>,
    onDismiss: () -> Unit
) {
    val logged = items.filter { !it.log.isNullOrBlank() }.sortedBy { it.id }
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .background(Color(0xFF0A0E0A))
                .systemBarsPadding()
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(start = 16.dp, end = 4.dp, top = 8.dp, bottom = 8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(
                    Icons.Filled.Terminal,
                    contentDescription = null,
                    tint = Color(0xFF8FD3A0),
                    modifier = Modifier.size(20.dp)
                )
                Spacer(Modifier.size(8.dp))
                Text(
                    "Terminal",
                    style = MaterialTheme.typography.titleMedium,
                    color = Color(0xFF8FD3A0),
                    fontFamily = FontFamily.Monospace
                )
                Spacer(Modifier.weight(1f))
                IconButton(onClick = onDismiss) {
                    Icon(Icons.Filled.Close, contentDescription = "Close", tint = Color(0xFFC6D6C6))
                }
            }
            if (logged.isEmpty()) {
                Text(
                    "No terminal output yet.\nStart a download and come back.",
                    style = MaterialTheme.typography.bodySmall,
                    fontFamily = FontFamily.Monospace,
                    color = Color(0xFF7DA67D),
                    modifier = Modifier.padding(16.dp)
                )
            } else {
                val listState = rememberLazyListState()
                LazyColumn(
                    state = listState,
                    modifier = Modifier.weight(1f),
                    contentPadding = PaddingValues(
                        start = 16.dp, end = 16.dp, top = 4.dp, bottom = 16.dp
                    )
                ) {
                    logged.forEach { entry ->
                        item(key = "h" + entry.id) {
                            Text(
                                "-- # " + entry.id + " : " + entry.title +
                                    " [" + statusShort(entry) + "] --",
                                style = MaterialTheme.typography.labelMedium,
                                fontFamily = FontFamily.Monospace,
                                color = Color(0xFF6BD98A),
                                modifier = Modifier.padding(top = 10.dp, bottom = 4.dp)
                            )
                        }
                        entry.log.orEmpty().lines().forEachIndexed { i, line ->
                            item(key = "l" + entry.id + "_" + i) {
                                Text(
                                    line.ifBlank { " " },
                                    style = MaterialTheme.typography.bodySmall,
                                    fontFamily = FontFamily.Monospace,
                                    fontSize = 11.sp,
                                    color = logLineColor(line)
                                )
                            }
                        }
                    }
                }
                LaunchedEffect(logged.size, logged.lastOrNull()?.log?.length) {
                    val n = listState.layoutInfo.totalItemsCount
                    if (n > 0) {
                        listState.scrollToItem(n - 1)
                    }
                }
            }
        }
    }
}

private fun statusShort(item: DownloadEntity): String = when (item.status) {
    DownloadEntity.STATUS_QUEUED -> "QUEUED"
    DownloadEntity.STATUS_RUNNING -> "RUNNING"
    DownloadEntity.STATUS_SAVING -> "SAVING"
    DownloadEntity.STATUS_COMPLETED -> "COMPLETED"
    DownloadEntity.STATUS_CANCELED -> "CANCELED"
    DownloadEntity.STATUS_FAILED -> "FAILED"
    else -> item.status
}

private fun statusText(item: DownloadEntity): String = when (item.status) {
    DownloadEntity.STATUS_QUEUED -> "Queued"
    DownloadEntity.STATUS_RUNNING -> "Downloading"
    DownloadEntity.STATUS_SAVING -> "Saving"
    DownloadEntity.STATUS_COMPLETED -> "Completed"
    DownloadEntity.STATUS_CANCELED -> "Canceled"
    DownloadEntity.STATUS_FAILED -> "Failed"
    else -> item.status
}

private fun logLineColor(line: String): Color = when {
    line.startsWith("$") -> Color(0xFF7FD1FF)
    line.startsWith("ERROR", ignoreCase = true) -> Color(0xFFEF6C6C)
    line.contains("conversion failed", ignoreCase = true) -> Color(0xFFEF6C6C)
    line.startsWith("[download]") -> Color(0xFF8FD3A0)
    line.startsWith("[Merger]") || line.startsWith("[ExtractAudio]") -> Color(0xFF7FD1FF)
    else -> Color(0xFFC6D6C6)
}

private fun openSavedFile(context: Context, uriString: String) {
    val uri = Uri.parse(uriString)
    val intent = Intent(Intent.ACTION_VIEW).apply {
        setDataAndType(uri, "*/*")
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }
    runCatching { context.startActivity(intent) }
}
