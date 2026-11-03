package com.ffmux.app.ui.home

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.rounded.ArrowDropDown
import androidx.compose.material.icons.rounded.Audiotrack
import androidx.compose.material.icons.rounded.Code
import androidx.compose.material.icons.rounded.ContentCut
import androidx.compose.material.icons.rounded.Download
import androidx.compose.material.icons.rounded.Flag
import androidx.compose.material.icons.rounded.Image
import androidx.compose.material.icons.rounded.Label
import androidx.compose.material.icons.rounded.PushPin
import androidx.compose.material.icons.rounded.Subtitles
import androidx.compose.material.icons.rounded.Timer
import androidx.compose.material.icons.rounded.Videocam
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import coil.compose.AsyncImage
import com.ffmux.app.Graph
import com.ffmux.app.engine.FormatKind
import com.ffmux.app.engine.FormatOption
import com.ffmux.app.engine.VideoInfo
import com.ffmux.app.ui.common.ScreenHeader
import com.ffmux.app.util.UrlUtils

@Composable
fun HomeScreen(
    onDownloadStarted: () -> Unit,
    viewModel: HomeViewModel = viewModel()
) {
    val clipboard = LocalClipboardManager.current
    val engineReady by Graph.engineReady.collectAsState()

    // One circular action: when the field is empty the clipboard link is
    // pasted in first, then the video info is fetched right away.
    val onFetchClicked: () -> Unit = {
        if (viewModel.url.isBlank()) {
            val text = clipboard.getText()?.text ?: ""
            UrlUtils.extractFirstUrl(text)?.let { pasted ->
                viewModel.updateUrl(pasted)
            }
        }
        viewModel.fetch()
    }

    Column(modifier = Modifier.fillMaxSize()) {
        ScreenHeader(title = "Download")

        val current = viewModel.state
        // Keep the fetched info on screen while a re-fetch is running or
        // when it fails, so the format list never collapses.
        var lastInfo by remember { mutableStateOf<HomeUiState.Info?>(null) }
        (current as? HomeUiState.Info)?.let { lastInfo = it }
        val infoState = current as? HomeUiState.Info ?: lastInfo
        val loading = current is HomeUiState.Loading
        val errorState = current as? HomeUiState.Error

        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp)
        ) {
            if (!engineReady) {
                LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
                Text(
                    "Preparing the yt-dlp engine... (first launch only)",
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
                    if (viewModel.url.isNotEmpty()) {
                        IconButton(onClick = { viewModel.updateUrl("") }) {
                            Icon(Icons.Filled.Close, contentDescription = "Clear")
                        }
                    }
                }
            )

            // While the format cards are on screen the big circular button
            // is replaced by this full-width one right under the link field.
            if (infoState != null) {
                Spacer(Modifier.height(12.dp))
                HorizontalFetchButton(loading = loading, onClick = onFetchClicked)
                Spacer(Modifier.height(12.dp))
            }
        }

        if (infoState != null) {
            Column(
                modifier = Modifier
                    .weight(1f)
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                errorState?.let {
                    Text(
                        text = it.message,
                        color = MaterialTheme.colorScheme.error,
                        style = MaterialTheme.typography.bodyMedium,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.fillMaxWidth()
                    )
                }

                InfoCard(
                    info = infoState.info,
                    title = viewModel.editableTitle,
                    onTitleChange = { viewModel.updateTitle(it) },
                    uploader = viewModel.editableUploader,
                    onUploaderChange = { viewModel.updateUploader(it) }
                )

                Text("Format", style = MaterialTheme.typography.titleMedium)
                BestCard(
                    option = infoState.sections.best,
                    selected = viewModel.bestSelected,
                    onClick = { viewModel.selectBest() }
                )

                if (infoState.sections.video.isNotEmpty()) {
                    Text("Video", style = MaterialTheme.typography.titleMedium)
                    FormatGrid(
                        options = infoState.sections.video,
                        selected = viewModel.selectedVideo,
                        onToggle = { viewModel.toggleVideo(it) }
                    )
                }

                if (infoState.sections.audio.isNotEmpty()) {
                    Text("Audio", style = MaterialTheme.typography.titleMedium)
                    FormatGrid(
                        options = infoState.sections.audio,
                        selected = viewModel.selectedAudio,
                        onToggle = { viewModel.toggleAudio(it) }
                    )
                }

                Text("Options", style = MaterialTheme.typography.titleMedium)
                OptionChips(
                    embedThumbnail = viewModel.embedThumbnail,
                    onThumbnailToggle = { viewModel.toggleEmbedThumbnail() },
                    embedMetadata = viewModel.embedMetadata,
                    onMetadataToggle = { viewModel.toggleEmbedMetadata() },
                    splitChapters = viewModel.splitChapters,
                    onChaptersToggle = { viewModel.toggleSplitChapters() },
                    noPart = viewModel.noPart,
                    onNoPartToggle = { viewModel.toggleNoPart() },
                    subLangs = viewModel.subLangs,
                    onSubLangsChange = { viewModel.updateSubLangs(it) },
                    recordMinutes = viewModel.recordMinutes,
                    onRecordMinutesChange = { viewModel.updateRecordMinutes(it) },
                    extraArgs = viewModel.extraArgs,
                    onExtraArgsChange = { viewModel.updateExtraArgs(it) },
                    commandPreview = { draft ->
                        buildCommandPreview(
                            selector = viewModel.selectedSelector(),
                            baseArgs = viewModel.baseDownloadArgs(),
                            extraArgs = draft,
                            url = (viewModel.state as? HomeUiState.Info)?.fetchedUrl
                                ?: viewModel.url,
                            title = viewModel.editableTitle
                        )
                    },
                    durationNote = if (viewModel.recordMinutes > 0) {
                        "stops after ${durationText(viewModel.recordMinutes)} (enforced by FFMux)"
                    } else {
                        null
                    }
                )
                Spacer(Modifier.height(8.dp))
            }

            StickyDownloadBar(
                enabled = viewModel.selectedSelector() != null,
                sizeBytes = viewModel.selectedSizeBytes(),
                videoOnly = viewModel.isVideoOnlySelection(),
                onClick = { viewModel.startDownload(onDownloadStarted) }
            )
        } else {
            // Idle / loading / error: the big circular button sits in
            // the middle of the free page area.
            Box(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth(),
                contentAlignment = Alignment.Center
            ) {
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    modifier = Modifier.padding(horizontal = 24.dp)
                ) {
                    CircularFetchButton(loading = loading, onClick = onFetchClicked)
                    if (errorState != null) {
                        Spacer(Modifier.height(20.dp))
                        Text(
                            text = errorState.message,
                            color = MaterialTheme.colorScheme.error,
                            style = MaterialTheme.typography.bodyMedium,
                            textAlign = TextAlign.Center
                        )
                    }
                }
            }
        }
    }
}

/**
 * Big circular main action in the middle of the page: pastes the
 * clipboard link into the field when it is empty, then fetches the
 * video info. While fetching it turns into a spinner.
 */
@Composable
private fun CircularFetchButton(
    loading: Boolean,
    onClick: () -> Unit
) {
    Box(
        modifier = Modifier.fillMaxWidth(),
        contentAlignment = Alignment.Center
    ) {
        FilledIconButton(
            onClick = onClick,
            enabled = !loading,
            modifier = Modifier.size((LocalConfiguration.current.screenWidthDp * 0.5f).dp),
            shape = androidx.compose.foundation.shape.CircleShape
        ) {
            if (loading) {
                CircularProgressIndicator(
                    modifier = Modifier.size((LocalConfiguration.current.screenWidthDp * 0.20f).dp),
                    strokeWidth = (LocalConfiguration.current.screenWidthDp * 0.015f).dp,
                    color = MaterialTheme.colorScheme.onPrimary
                )
            } else {
                Icon(
                    imageVector = Icons.Rounded.Download,
                    contentDescription = "Paste link and fetch",
                    modifier = Modifier.size((LocalConfiguration.current.screenWidthDp * 0.22f).dp)
                )
            }
        }
    }
}

/**
 * Full-width replacement for the circular button while the format cards
 * are on screen: sits right under the link field, keeps the same
 * paste-then-fetch action and turns into a spinner while fetching.
 * Shares its exact height, shape and font with the Download bar.
 */
@Composable
private fun HorizontalFetchButton(
    loading: Boolean,
    onClick: () -> Unit
) {
    val style = rememberBigButtonStyle()
    Button(
        onClick = onClick,
        enabled = !loading,
        modifier = Modifier
            .fillMaxWidth()
            .height(style.height),
        shape = MaterialTheme.shapes.large
    ) {
        if (loading) {
            CircularProgressIndicator(
                modifier = Modifier.size(22.dp),
                strokeWidth = 2.dp,
                color = MaterialTheme.colorScheme.onPrimary
            )
            Spacer(Modifier.width(10.dp))
            Text(
                "Fetching...",
                fontSize = style.fontSize,
                fontWeight = FontWeight.Medium,
                maxLines = 1
            )
        } else {
            Icon(
                imageVector = Icons.Rounded.Download,
                contentDescription = null,
                modifier = Modifier.size(24.dp)
            )
            Spacer(Modifier.width(10.dp))
            Text(
                "Get quality",
                fontSize = style.fontSize,
                fontWeight = FontWeight.Medium,
                maxLines = 1
            )
        }
    }
}

/** Shared look of the two big full-width buttons: same height, same font. */
private data class BigButtonStyle(val height: Dp, val fontSize: TextUnit)

/**
 * One screen-relative style for the "Get quality" button and the sticky
 * "Download" bar: 14% of the screen width high (48..64dp) and a font of
 * 5% of the screen width (17..21sp), so the two always match on every
 * phone and the label scales with the button.
 */
@Composable
private fun rememberBigButtonStyle(): BigButtonStyle {
    val config = LocalConfiguration.current
    return BigButtonStyle(
        height = (config.screenWidthDp * 0.14f).coerceIn(48f, 64f).dp,
        fontSize = (config.screenWidthDp * 0.05f).coerceIn(17f, 21f).sp
    )
}

/**
 * Chip with a dropdown arrow for the recording time limit: the left
 * side shows the chosen time (or "Duration" when off), the arrow on
 * the right opens the picker -- exactly like ( 2m | v ).
 */
@Composable
private fun DurationChip(
    minutes: Int,
    onClick: () -> Unit
) {
    val selected = minutes > 0
    val animatedOutline by animateColorAsState(
        targetValue = if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outlineVariant,
        animationSpec = tween(100), label = "durationOutline"
    )
    val animatedContainer by animateColorAsState(
        targetValue = if (selected) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surface,
        animationSpec = tween(100), label = "durationContainer"
    )
    val animatedTitle by animateColorAsState(
        targetValue = if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface,
        animationSpec = tween(100), label = "durationTitle"
    )
    Row(
        modifier = Modifier
            .clip(androidx.compose.foundation.shape.CircleShape)
            .selectable(selected = selected, onClick = onClick)
            .border(1.dp, animatedOutline, androidx.compose.foundation.shape.CircleShape)
            .background(animatedContainer)
            .padding(start = 14.dp, end = 10.dp, top = 10.dp, bottom = 10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(
            Icons.Rounded.Timer,
            contentDescription = null,
            tint = animatedOutline,
            modifier = Modifier.size(16.dp)
        )
        Spacer(Modifier.width(6.dp))
        Text(
            text = durationLabel(minutes),
            style = MaterialTheme.typography.labelLarge,
            color = animatedTitle
        )
        Spacer(Modifier.width(6.dp))
        // Thin divider between the label and the dropdown arrow.
        Box(
            modifier = Modifier
                .width(1.dp)
                .height(16.dp)
                .background(animatedOutline.copy(alpha = 0.4f))
        )
        Icon(
            Icons.Rounded.ArrowDropDown,
            contentDescription = "Pick a duration",
            tint = animatedOutline,
            modifier = Modifier.size(18.dp)
        )
    }
}

/** Recording time presets in minutes; 0 means "No limit". */
private val durationPresets = listOf(0, 1, 2, 5, 10, 15, 30, 45, 60, 90, 120, 180)

/**
 * Picker for the recording time limit: common presets from one minute
 * to three hours plus a custom minutes field. The limit is enforced by
 * the download service, which stops yt-dlp and saves the captured file.
 */
@Composable
private fun DurationDialog(
    minutes: Int,
    onDismiss: () -> Unit,
    onConfirm: (Int) -> Unit
) {
    var picked by remember { mutableStateOf(if (minutes in durationPresets) minutes else 0) }
    var custom by remember {
        mutableStateOf(if (minutes !in durationPresets && minutes > 0) minutes.toString() else "")
    }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Recording duration") },
        text = {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(max = 340.dp)
                    .verticalScroll(rememberScrollState())
            ) {
                Text(
                    "Stop the download this long after it starts. " +
                        "Useful for recording live streams.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Spacer(Modifier.height(10.dp))
                durationPresets.forEach { preset ->
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(MaterialTheme.shapes.extraSmall)
                            .selectable(selected = picked == preset, onClick = { picked = preset })
                            .padding(vertical = 4.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        RadioButton(selected = picked == preset, onClick = { picked = preset })
                        Spacer(Modifier.width(10.dp))
                        Text(
                            text = if (preset == 0) "No limit" else durationText(preset),
                            style = MaterialTheme.typography.bodyLarge
                        )
                    }
                }
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(MaterialTheme.shapes.extraSmall)
                        .selectable(selected = picked == -1, onClick = { picked = -1 })
                        .padding(vertical = 4.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    RadioButton(selected = picked == -1, onClick = { picked = -1 })
                    Spacer(Modifier.width(10.dp))
                    OutlinedTextField(
                        value = custom,
                        onValueChange = {
                            custom = it.filter { ch -> ch.isDigit() }.take(4)
                            picked = -1
                        },
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text("Custom minutes") },
                        singleLine = true,
                        shape = MaterialTheme.shapes.small
                    )
                }
            }
        },
        confirmButton = {
            TextButton(onClick = {
                val value = when {
                    picked == -1 -> custom.toIntOrNull()?.coerceIn(1, 1440) ?: 0
                    else -> picked
                }
                onConfirm(value)
            }) { Text("Done") }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Cancel") }
        }
    )
}

/**
 * Shows the exact yt-dlp command that FFMux will run -- updated live
 * while typing -- and lets you add or remove extra arguments on top.
 */
@Composable
private fun ExtraCommandsDialog(
    initialArgs: String,
    commandPreview: (String) -> String,
    durationNote: String?,
    onDismiss: () -> Unit,
    onConfirm: (String) -> Unit
) {
    var text by remember { mutableStateOf(initialArgs) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Extra commands") },
        text = {
            Column(modifier = Modifier.fillMaxWidth()) {
                Text(
                    "The exact command that will run:",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Spacer(Modifier.height(8.dp))
                Surface(
                    modifier = Modifier.fillMaxWidth(),
                    shape = MaterialTheme.shapes.small,
                    color = MaterialTheme.colorScheme.surfaceContainerHighest
                ) {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .heightIn(max = 170.dp)
                            .verticalScroll(rememberScrollState())
                            .padding(10.dp)
                    ) {
                        SelectionContainer {
                            Text(
                                text = commandPreview(text),
                                style = MaterialTheme.typography.bodySmall.copy(
                                    fontFamily = FontFamily.Monospace,
                                    lineHeight = 16.sp
                                )
                            )
                        }
                        if (durationNote != null) {
                            Spacer(Modifier.height(6.dp))
                            Text(
                                text = durationNote,
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                }
                Spacer(Modifier.height(12.dp))
                OutlinedTextField(
                    value = text,
                    onValueChange = { text = it },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("Additional arguments") },
                    placeholder = { Text("--retries 20 --limit-rate 2M") },
                    minLines = 2,
                    shape = MaterialTheme.shapes.small
                )
                Spacer(Modifier.height(6.dp))
                Text(
                    "Space separated yt-dlp arguments. They are appended to the command above and stay attached to this download.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        },
        confirmButton = {
            TextButton(onClick = { onConfirm(text) }) { Text("Done") }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Cancel") }
        }
    )
}

private fun durationLabel(minutes: Int): String =
    if (minutes <= 0) "Duration" else durationText(minutes)

private fun durationText(minutes: Int): String {
    val h = minutes / 60
    val m = minutes % 60
    return when {
        h > 0 && m > 0 -> "${h}h ${m}m"
        h > 0 -> "${h}h"
        else -> "${m}m"
    }
}

/**
 * Human readable preview of the yt-dlp invocation, mirroring the option
 * order the engine really uses in YtDlpEngine.download().
 */
private fun buildCommandPreview(
    selector: String?,
    baseArgs: String,
    extraArgs: String,
    url: String,
    title: String
): String {
    val parts = mutableListOf("yt-dlp", "--no-playlist")
    parts.add("-f")
    parts.add(selector ?: "bestvideo*+bestaudio/best")
    parts.add("-o")
    parts.add("\"${title.trim().ifBlank { "Untitled" }.take(40)}.%(ext)s\"")
    parts.add("--no-mtime")
    parts.add("--retries")
    parts.add("10")
    parts.add("--fragment-retries")
    parts.add("10")
    parts.add("--socket-timeout")
    parts.add("30")
    if (selector != null && selector.contains('+')) {
        parts.add("--merge-output-format")
        parts.add("mp4/mkv")
    }
    baseArgs.split(Regex("\\s+")).filter { it.isNotBlank() }.forEach { parts.add(it) }
    extraArgs.replace(Regex("[\\r\\n\\t]+"), " ").trim()
        .split(Regex("\\s+")).filter { it.isNotBlank() }.forEach { parts.add(it) }
    parts.add(url)
    return parts.joinToString(" ")
}

/** One yt-dlp feature toggle chip, ytdlnis style. */
@Composable
private fun OptionChip(
    label: String,
    icon: ImageVector,
    selected: Boolean,
    onClick: () -> Unit
) {
    val animatedOutline by animateColorAsState(
        targetValue = if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outlineVariant,
        animationSpec = tween(100), label = "chipOutline"
    )
    val animatedContainer by animateColorAsState(
        targetValue = if (selected) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surface,
        animationSpec = tween(100), label = "chipContainer"
    )
    val animatedTitle by animateColorAsState(
        targetValue = if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface,
        animationSpec = tween(100), label = "chipTitle"
    )
    Row(
        modifier = Modifier
            .clip(androidx.compose.foundation.shape.CircleShape)
            .selectable(selected = selected, onClick = onClick)
            .border(1.dp, animatedOutline, androidx.compose.foundation.shape.CircleShape)
            .background(animatedContainer)
            .padding(start = 14.dp, end = 18.dp, top = 10.dp, bottom = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Icon(icon, contentDescription = null, tint = animatedOutline, modifier = Modifier.size(16.dp))
        Text(label, style = MaterialTheme.typography.labelLarge, color = animatedTitle)
    }
}

/** Row of yt-dlp option chips shown under the quality cards. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun OptionChips(
    embedThumbnail: Boolean,
    onThumbnailToggle: () -> Unit,
    embedMetadata: Boolean,
    onMetadataToggle: () -> Unit,
    splitChapters: Boolean,
    onChaptersToggle: () -> Unit,
    noPart: Boolean,
    onNoPartToggle: () -> Unit,
    subLangs: Set<String>,
    onSubLangsChange: (Set<String>) -> Unit,
    recordMinutes: Int,
    onRecordMinutesChange: (Int) -> Unit,
    extraArgs: String,
    onExtraArgsChange: (String) -> Unit,
    commandPreview: (String) -> String,
    durationNote: String?
) {
    var showSubDialog by rememberSaveable { mutableStateOf(false) }
    var showDurationDialog by rememberSaveable { mutableStateOf(false) }
    var showExtraDialog by rememberSaveable { mutableStateOf(false) }

    FlowRow(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        OptionChip(
            label = "Thumbnail",
            icon = Icons.Rounded.Image,
            selected = embedThumbnail,
            onClick = onThumbnailToggle
        )
        OptionChip(
            label = subLangsLabel(subLangs),
            icon = Icons.Rounded.Subtitles,
            selected = subLangs.isNotEmpty(),
            onClick = { showSubDialog = true }
        )
        OptionChip(
            label = "Metadata",
            icon = Icons.Rounded.Label,
            selected = embedMetadata,
            onClick = onMetadataToggle
        )
        OptionChip(
            label = "Chapters",
            icon = Icons.Rounded.ContentCut,
            selected = splitChapters,
            onClick = onChaptersToggle
        )
        OptionChip(
            label = "--no-part",
            icon = Icons.Rounded.Flag,
            selected = noPart,
            onClick = onNoPartToggle
        )
        DurationChip(
            minutes = recordMinutes,
            onClick = { showDurationDialog = true }
        )
        OptionChip(
            label = "Extra commands",
            icon = Icons.Rounded.Code,
            selected = extraArgs.isNotBlank(),
            onClick = { showExtraDialog = true }
        )
    }

    if (showSubDialog) {
        SubtitleLangDialog(
            selected = subLangs,
            onDismiss = { showSubDialog = false },
            onConfirm = { langs ->
                onSubLangsChange(langs)
                showSubDialog = false
            }
        )
    }
    if (showDurationDialog) {
        DurationDialog(
            minutes = recordMinutes,
            onDismiss = { showDurationDialog = false },
            onConfirm = { minutes ->
                onRecordMinutesChange(minutes)
                showDurationDialog = false
            }
        )
    }
    if (showExtraDialog) {
        ExtraCommandsDialog(
            initialArgs = extraArgs,
            commandPreview = commandPreview,
            durationNote = durationNote,
            onDismiss = { showExtraDialog = false },
            onConfirm = { args ->
                onExtraArgsChange(args)
                showExtraDialog = false
            }
        )
    }
}

private fun subLangsLabel(langs: Set<String>): String {
    if (langs.isEmpty()) return "Subtitles"
    return "Subtitles " + langs.sorted().joinToString(",")
}

private data class SubLang(val code: String, val name: String)

/** English and Persian are pinned to the top of the list. */
private val pinnedSubLangs = listOf(
    SubLang("en", "English"),
    SubLang("fa", "Persian")
)

private val otherSubLangs = listOf(
    SubLang("ar", "Arabic"),
    SubLang("de", "German"),
    SubLang("es", "Spanish"),
    SubLang("fr", "French"),
    SubLang("hi", "Hindi"),
    SubLang("id", "Indonesian"),
    SubLang("it", "Italian"),
    SubLang("ja", "Japanese"),
    SubLang("ko", "Korean"),
    SubLang("nl", "Dutch"),
    SubLang("pl", "Polish"),
    SubLang("pt", "Portuguese"),
    SubLang("ru", "Russian"),
    SubLang("tr", "Turkish"),
    SubLang("ur", "Urdu"),
    SubLang("zh-Hans", "Chinese (Simplified)")
)

/**
 * Multi-select list of subtitle languages to embed into the video
 * (--embed-subs --sub-langs ...). English and Persian sit pinned at
 * the top, every other common language follows below the divider.
 */
@Composable
private fun SubtitleLangDialog(
    selected: Set<String>,
    onDismiss: () -> Unit,
    onConfirm: (Set<String>) -> Unit
) {
    var picked by remember { mutableStateOf(selected) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Embed subtitles") },
        text = {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(max = 340.dp)
                    .verticalScroll(rememberScrollState())
            ) {
                Text(
                    "Pick the subtitle languages to embed into the video file.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Spacer(Modifier.height(10.dp))
                pinnedSubLangs.forEach { lang ->
                    SubLangRow(
                        lang = lang,
                        pinned = true,
                        checked = lang.code in picked,
                        onToggle = {
                            picked = if (lang.code in picked) picked - lang.code else picked + lang.code
                        }
                    )
                }
                HorizontalDivider(
                    modifier = Modifier.padding(vertical = 6.dp),
                    color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f)
                )
                otherSubLangs.forEach { lang ->
                    SubLangRow(
                        lang = lang,
                        pinned = false,
                        checked = lang.code in picked,
                        onToggle = {
                            picked = if (lang.code in picked) picked - lang.code else picked + lang.code
                        }
                    )
                }
            }
        },
        confirmButton = {
            TextButton(onClick = { onConfirm(picked) }) { Text("Done") }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Cancel") }
        }
    )
}

@Composable
private fun SubLangRow(
    lang: SubLang,
    pinned: Boolean,
    checked: Boolean,
    onToggle: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(MaterialTheme.shapes.extraSmall)
            .selectable(selected = checked, onClick = onToggle)
            .padding(vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Checkbox(checked = checked, onCheckedChange = null)
        Spacer(Modifier.width(10.dp))
        Column {
            Text(lang.name, style = MaterialTheme.typography.bodyLarge)
            Text(
                lang.code,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        Spacer(Modifier.weight(1f))
        if (pinned) {
            Icon(
                imageVector = Icons.Rounded.PushPin,
                contentDescription = "Pinned",
                modifier = Modifier.size(14.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
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

/** Full-width shortcut card for the combined best video + audio format. */
@Composable
private fun BestCard(
    option: FormatOption,
    selected: Boolean,
    onClick: () -> Unit
) {
    val outlineColor = MaterialTheme.colorScheme.primary
    val containerColor = MaterialTheme.colorScheme.primaryContainer
    val animatedOutline by animateColorAsState(
        targetValue = if (selected) outlineColor else MaterialTheme.colorScheme.outlineVariant,
        animationSpec = tween(100), label = "bestOutline"
    )
    val animatedContainer by animateColorAsState(
        targetValue = if (selected) containerColor else MaterialTheme.colorScheme.surface,
        animationSpec = tween(100), label = "bestContainer"
    )
    val animatedTitle by animateColorAsState(
        targetValue = if (selected) outlineColor else MaterialTheme.colorScheme.onSurface,
        animationSpec = tween(100), label = "bestTitle"
    )
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 64.dp)
            .clip(MaterialTheme.shapes.small)
            .selectable(selected = selected, onClick = onClick)
            .border(1.dp, animatedOutline, MaterialTheme.shapes.small)
            .background(animatedContainer)
    ) {
        Row(
            modifier = Modifier
                .align(Alignment.CenterStart)
                .padding(start = 14.dp, top = 10.dp, bottom = 10.dp, end = 48.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                imageVector = Icons.Rounded.Videocam,
                contentDescription = "Video",
                tint = animatedOutline,
                modifier = Modifier.size(18.dp)
            )
            Icon(
                imageVector = Icons.Rounded.Audiotrack,
                contentDescription = "Audio",
                tint = animatedOutline,
                modifier = Modifier
                    .size(18.dp)
                    .padding(start = 2.dp)
            )
            Spacer(Modifier.width(10.dp))
            Column {
                Text(
                    text = option.label,
                    style = MaterialTheme.typography.titleSmall,
                    color = animatedTitle,
                    maxLines = 1
                )
                bestSpec(option)?.let {
                    Text(
                        text = it,
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
            }
        }
    }
}

/** Two-column grid of quality cards for one section. */
@Composable
private fun FormatGrid(
    options: List<FormatOption>,
    selected: Int,
    onToggle: (Int) -> Unit
) {
    options.chunked(2).forEachIndexed { rowIndex, rowOptions ->
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            rowOptions.forEachIndexed { colIndex, option ->
                val index = rowIndex * 2 + colIndex
                FormatCard(
                    option = option,
                    selected = selected == index,
                    onClick = { onToggle(index) },
                    modifier = Modifier.weight(1f)
                )
            }
            if (rowOptions.size == 1) {
                Spacer(modifier = Modifier.weight(1f))
            }
        }
    }
}

@Composable
private fun FormatCard(
    option: FormatOption,
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    val video = option.kind == FormatKind.VIDEO
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
            .heightIn(min = 88.dp)
            .clip(MaterialTheme.shapes.small)
            .selectable(selected = selected, onClick = onClick)
            .border(1.dp, animatedOutline, MaterialTheme.shapes.small)
            .background(animatedContainer)
    ) {
        Column(
            modifier = Modifier.padding(start = 12.dp, top = 12.dp, end = 12.dp, bottom = 28.dp)
        ) {
            Text(
                text = option.label,
                style = MaterialTheme.typography.titleSmall,
                color = animatedTitle,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            specLine1(option)?.let {
                Text(
                    text = it,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
            specLine2(option)?.let {
                Text(
                    text = it,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
        }
        Row(
            modifier = Modifier
                .align(Alignment.BottomEnd)
                .padding(6.dp),
            horizontalArrangement = Arrangement.spacedBy(2.dp)
        ) {
            if (video) {
                Icon(
                    imageVector = Icons.Rounded.Videocam,
                    contentDescription = "Video",
                    tint = animatedOutline,
                    modifier = Modifier.size(14.dp)
                )
            } else {
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

/** Sticky bar pinned above the bottom navigation while formats are shown. */
@Composable
private fun StickyDownloadBar(
    enabled: Boolean,
    sizeBytes: Long?,
    videoOnly: Boolean,
    onClick: () -> Unit
) {
    val style = rememberBigButtonStyle()
    val config = LocalConfiguration.current
    val subtitleFontSize = (config.screenWidthDp * 0.036f).coerceIn(12f, 15f).sp
    Surface(
        modifier = Modifier.fillMaxWidth(),
        color = MaterialTheme.colorScheme.surfaceContainer,
        tonalElevation = 3.dp
    ) {
        Button(
            onClick = onClick,
            enabled = enabled,
            modifier = Modifier
                .fillMaxWidth()
                .padding(start = 16.dp, end = 16.dp, top = 12.dp, bottom = 12.dp)
                .height(style.height),
            shape = MaterialTheme.shapes.large
        ) {
            // Single line: title and approximate size side by side.
            Text(
                text = "Download",
                fontSize = style.fontSize,
                fontWeight = FontWeight.Medium,
                maxLines = 1
            )
            Spacer(Modifier.width(10.dp))
            Text(
                text = downloadBarSubtitle(sizeBytes, videoOnly, enabled),
                fontSize = subtitleFontSize,
                color = androidx.compose.material3.LocalContentColor.current.copy(alpha = 0.75f),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
    }
}

private fun downloadBarSubtitle(sizeBytes: Long?, videoOnly: Boolean, enabled: Boolean): String {
    if (!enabled) return "Select a format above"
    val parts = mutableListOf<String>()
    if (videoOnly) parts.add("video only, no audio")
    when {
        sizeBytes == null -> {}
        else -> parts.add(0, "\u2248 ${byteSizeText(sizeBytes)}")
    }
    return if (parts.isEmpty()) "Ready to download" else parts.joinToString(" \u00B7 ")
}

private fun byteSizeText(bytes: Long): String {
    val mb = bytes / 1048576.0
    return when {
        mb >= 1024.0 -> String.format("%.1f GB", mb / 1024.0)
        mb >= 100.0 -> String.format("%.0f MB", mb)
        mb >= 1.0 -> String.format("%.1f MB", mb)
        else -> String.format("%.0f KB", bytes / 1024.0)
    }
}

private fun bestSpec(option: FormatOption): String? {
    val parts = mutableListOf<String>()
    option.note?.let { parts.add(it) }
    option.size?.let { parts.add("\u2248 $it") }
    if (parts.isEmpty()) return null
    return parts.joinToString(" \u00B7 ")
}

private fun specLine1(option: FormatOption): String? {
    val parts = mutableListOf<String>()
    option.formatId?.let { parts.add("ID $it") }
    option.ext?.let { parts.add(it) }
    if (option.kind == FormatKind.VIDEO) {
        option.fps?.let { parts.add("${it}fps") }
    }
    if (parts.isEmpty()) return null
    return parts.joinToString(" \u00B7 ")
}

private fun specLine2(option: FormatOption): String? {
    val parts = mutableListOf<String>()
    option.size?.let { parts.add("\u2248 $it") }
    option.kbps?.let { parts.add("${it} kbps") }
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
