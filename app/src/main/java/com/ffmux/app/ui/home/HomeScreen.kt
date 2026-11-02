package com.ffmux.app.ui.home

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ContentPaste
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.rounded.Audiotrack
import androidx.compose.material.icons.rounded.Videocam
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import coil.compose.AsyncImage
import com.ffmux.app.Graph
import com.ffmux.app.engine.FormatKind
import com.ffmux.app.engine.FormatOption
import com.ffmux.app.engine.VideoInfo
import com.ffmux.app.util.UrlUtils

@Composable
fun HomeScreen(
    onDownloadStarted: () -> Unit,
    viewModel: HomeViewModel = viewModel()
) {
    val clipboard = LocalClipboardManager.current
    val engineReady by Graph.engineReady.collectAsState()

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text("Download", style = MaterialTheme.typography.headlineMedium)

        if (!engineReady) {
            LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
            Text(
                "Preparing the yt-dlp engine… (first launch only)",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }

        OutlinedTextField(
            value = viewModel.url,
            onValueChange = { viewModel.updateUrl(it) },
            modifier = Modifier.fillMaxWidth(),
            label = { Text("Video URL") },
            singleLine = true,
            trailingIcon = {
                IconButton(onClick = {
                    val text = clipboard.getText()?.text ?: return@IconButton
                    UrlUtils.extractFirstUrl(text)?.let { pasted ->
                        viewModel.updateUrl(pasted)
                        viewModel.fetch()
                    }
                }) {
                    Icon(Icons.Filled.ContentPaste, contentDescription = "Paste")
                }
            }
        )

        Button(
            onClick = { viewModel.fetch() },
            modifier = Modifier.fillMaxWidth(),
            enabled = viewModel.url.isNotBlank() && viewModel.state !is HomeUiState.Loading
        ) {
            if (viewModel.state is HomeUiState.Loading) {
                CircularProgressIndicator(
                    modifier = Modifier.size(18.dp),
                    strokeWidth = 2.dp
                )
                Spacer(Modifier.width(8.dp))
                Text("Fetching…")
            } else {
                Text("Fetch info")
            }
        }

        when (val current = viewModel.state) {
            is HomeUiState.Error -> {
                Text(
                    current.message,
                    color = MaterialTheme.colorScheme.error,
                    style = MaterialTheme.typography.bodyMedium
                )
            }
            is HomeUiState.Info -> {
                InfoCard(
                    info = current.info,
                    title = viewModel.editableTitle,
                    onTitleChange = { viewModel.updateTitle(it) },
                    uploader = viewModel.editableUploader,
                    onUploaderChange = { viewModel.updateUploader(it) }
                )
                Text("Format", style = MaterialTheme.typography.titleMedium)
                current.options.chunked(2).forEachIndexed { rowIndex, rowOptions ->
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        rowOptions.forEachIndexed { colIndex, option ->
                            val index = rowIndex * 2 + colIndex
                            FormatCard(
                                option = option,
                                isBest = index == 0,
                                selected = index == viewModel.selectedFormat,
                                onClick = { viewModel.selectedFormat = index },
                                modifier = Modifier.weight(1f)
                            )
                        }
                        if (rowOptions.size == 1) {
                            Spacer(modifier = Modifier.weight(1f))
                        }
                    }
                }
                Button(
                    onClick = { viewModel.startDownload(onDownloadStarted) },
                    modifier = Modifier.fillMaxWidth(),
                    enabled = viewModel.selectedFormat >= 0
                ) {
                    Text("Download")
                }
            }
            else -> {}
        }
        Spacer(Modifier.height(8.dp))
    }
}

@Composable
private fun InfoCard(
    info: VideoInfo,
    title: String,
    onTitleChange: (String) -> Unit,
    uploader: String,
    onUploaderChange: (String) -> Unit
) {
    ElevatedCard(
        modifier = Modifier.fillMaxWidth(),
        shape = MaterialTheme.shapes.small
    ) {
        Column {
            Box(Modifier.fillMaxWidth()) {
                AsyncImage(
                    model = info.thumbnail,
                    contentDescription = null,
                    modifier = Modifier
                        .fillMaxWidth()
                        .aspectRatio(16f / 9f, matchHeightConstraintsFirst = true)
                        .clip(MaterialTheme.shapes.small),
                    contentScale = ContentScale.Crop
                )
                info.duration?.let { seconds ->
                    val config = LocalConfiguration.current
                    val durationFontSize =
                        (config.screenWidthDp * 0.038f).coerceIn(12f, 18f).sp
                    Surface(
                        modifier = Modifier
                            .padding(6.dp)
                            .align(Alignment.BottomEnd),
                        color = Color.Black.copy(alpha = 0.68f),
                        shape = MaterialTheme.shapes.extraSmall
                    ) {
                        Text(
                            modifier = Modifier.padding(horizontal = 6.dp, vertical = 1.dp),
                            text = formatDuration(seconds),
                            fontSize = durationFontSize,
                            lineHeight = (durationFontSize.value * 1.15f).sp,
                            fontWeight = FontWeight.Medium,
                            color = Color.White
                        )
                    }
                }
            }
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(12.dp),
                horizontalAlignment = Alignment.Start
            ) {
                OutlinedTextField(
                    value = title,
                    onValueChange = onTitleChange,
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("Title") },
                    singleLine = true,
                    textStyle = MaterialTheme.typography.titleMedium,
                    shape = MaterialTheme.shapes.small,
                    trailingIcon = {
                        Icon(
                            Icons.Outlined.Edit,
                            contentDescription = null,
                            modifier = Modifier.size(16.dp),
                            tint = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                )
                OutlinedTextField(
                    value = uploader,
                    onValueChange = onUploaderChange,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = 8.dp),
                    label = { Text("Author") },
                    singleLine = true,
                    textStyle = MaterialTheme.typography.bodyMedium,
                    shape = MaterialTheme.shapes.small
                )
            }
        }
    }
}

@Composable
private fun FormatCard(
    option: FormatOption,
    isBest: Boolean,
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    val video = option.kind == FormatKind.VIDEO
    val showAudio = option.kind == FormatKind.AUDIO || isBest
    val outlineColor: Color
    val containerColor: Color
    if (video) {
        outlineColor = MaterialTheme.colorScheme.primary
        containerColor = MaterialTheme.colorScheme.primaryContainer
    } else {
        outlineColor = MaterialTheme.colorScheme.secondary
        containerColor = MaterialTheme.colorScheme.secondaryContainer
    }
    val animatedOutline by animateColorAsState(
        targetValue = if (selected) outlineColor else MaterialTheme.colorScheme.outlineVariant,
        animationSpec = tween(100), label = "formatOutline"
    )
    val animatedContainer by animateColorAsState(
        targetValue = if (selected) containerColor else MaterialTheme.colorScheme.surface,
        animationSpec = tween(100), label = "formatContainer"
    )
    val animatedTitle by animateColorAsState(
        targetValue = if (selected) outlineColor else MaterialTheme.colorScheme.onSurface,
        animationSpec = tween(100), label = "formatTitle"
    )
    Box(
        modifier = modifier
            .clip(MaterialTheme.shapes.small)
            .selectable(selected = selected, onClick = onClick)
            .border(1.dp, animatedOutline, MaterialTheme.shapes.small)
            .background(animatedContainer)
    ) {
        Column(
            modifier = Modifier.padding(start = 10.dp, top = 8.dp, end = 10.dp, bottom = 22.dp)
        ) {
            Text(
                text = option.label,
                style = MaterialTheme.typography.titleSmall,
                color = animatedTitle,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            formatSpec(option)?.let {
                Text(
                    text = it,
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
        }
        Row(
            modifier = Modifier
                .align(Alignment.BottomEnd)
                .padding(4.dp),
            horizontalArrangement = Arrangement.spacedBy(2.dp)
        ) {
            if (video) {
                Icon(
                    imageVector = Icons.Rounded.Videocam,
                    contentDescription = "Video",
                    tint = animatedOutline,
                    modifier = Modifier.size(14.dp)
                )
            }
            if (showAudio) {
                Icon(
                    imageVector = Icons.Rounded.Audiotrack,
                    contentDescription = "Audio",
                    tint = animatedOutline,
                    modifier = Modifier.size(14.dp)
                )
            }
        }
    }
}

private fun formatSpec(option: FormatOption): String? {
    option.note?.let { return it }
    val parts = mutableListOf<String>()
    option.ext?.let { parts.add(it) }
    if (option.kind == FormatKind.AUDIO) {
        option.kbps?.let { parts.add("${it} kbps") }
    } else {
        option.fps?.let { parts.add("${it} fps") }
    }
    option.size?.let { parts.add(it) }
    if (parts.isEmpty()) return null
    return parts.joinToString(" \u00B7 ")
}

private fun formatDuration(seconds: Long): String {
    val h = seconds / 3600
    val m = (seconds % 3600) / 60
    val s = seconds % 60
    return if (h > 0) {
        String.format("%d:%02d:%02d", h, m, s)
    } else {
        String.format("%d:%02d", m, s)
    }
}
