#!/usr/bin/env bash
###############################################################################
# FFMux patch 11 (v1.4.4) -- full source installer for the touched files.
# Run from the repository root:  bash apply-changes.sh
#
# Like patch 10, this script installs the COMPLETE source of every file
# it touches, so whatever state the tree is in the result is byte-for-
# byte the verified tree below. Running it twice changes nothing
# (content-stable, so the CI commit step stays a no-op).
#
# What is new (patch 11), on top of everything from patches 1-10:
#   1. Square reset button left of the sticky "Download" button: 1:1
#      (exactly the Download height, 14% of the screen width clamped
#      to 48..64dp), rounded corners, tonal color so Download stays
#      the primary action. One tap wipes the loaded link, the video
#      info, the formats, the selections and the per-link recording
#      limit, and returns to the empty start page with the big
#      circular button. Option chips keep their values (they are user
#      preferences, not link state). A fetch that is still running
#      when the button is pressed is dropped (generation counter), so
#      stale info can never pop back in. Downloads already sitting in
#      the queue are NOT touched.
#   2. The "Extra commands" dialog is now ytdlnis sized: nearly the
#      full screen width (96%) and 78% of the screen height (92% in
#      landscape). The monospace command preview fills all the free
#      space instead of a 170dp box, so long commands stay readable.
#
# App version after this script: 1.4.4 (versionCode 11).
#
# Files installed under app/src/main/java/com/ffmux/app/ (2 files):
#   ui/home/HomeScreen.kt  ui/home/HomeViewModel.kt
# Precondition: the tree already carries patch 10 (v1.4.3); this is
# verified up front and the script fails loudly if it is missing.
# Also touched: app/build.gradle.kts (version bump only).
###############################################################################
set -euo pipefail
if LC_ALL=C grep -qn '[^ -~]' "$0"; then
    echo "FATAL: non-ascii byte in this script"
    exit 1
fi

BASE="app/src/main/java/com/ffmux/app"
HOME_KT="$BASE/ui/home/HomeScreen.kt"
VM_KT="$BASE/ui/home/HomeViewModel.kt"
SVC_KT="$BASE/engine/DownloadService.kt"
DB_KT="$BASE/data/db/AppDatabase.kt"
ENT_KT="$BASE/data/db/DownloadEntity.kt"
GRAPH_KT="$BASE/Graph.kt"
BUILD_G="app/build.gradle.kts"

for f in "$HOME_KT" "$VM_KT" "$SVC_KT" "$DB_KT" "$ENT_KT" "$GRAPH_KT" "$BUILD_G"; do
    if [ ! -f "$f" ]; then
        echo "FATAL: $f not found - run from the repository root"
        exit 1
    fi
done

# --- Preconditions: patch 10 must already be applied. -------------------------
precondition() {
    if ! grep -qF "$2" "$1"; then
        echo "FATAL: $1 does not contain: $2"
        echo "       patch 10 (v1.4.3) seems to be missing - apply it first"
        exit 1
    fi
}
precondition "$SVC_KT"   'stripPartFiles'
precondition "$SVC_KT"   'timedOut'
precondition "$DB_KT"    'MIGRATION_2_3'
precondition "$ENT_KT"   'recordMinutes: Int = 0'
precondition "$GRAPH_KT" 'MIGRATION_2_3'
echo "  [ok] patch 10 state verified (duration limit + extra commands present)"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

echo "== FFMux patch 11: reset button + full-screen extra commands =="

mkdir -p "$STAGE/ui/home"
cat > "$STAGE/ui/home/HomeScreen.kt" <<'FFMUX_EOF_HOME11'
package com.ffmux.app.ui.home

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
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
import androidx.compose.material.icons.rounded.Close
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
import androidx.compose.material3.FilledTonalIconButton
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
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
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
        // when it fails, so the format list never collapses. Going back
        // to Idle (the reset button next to Download) drops the cache
        // with it, so the start page comes back clean.
        var lastInfo by remember { mutableStateOf<HomeUiState.Info?>(null) }
        (current as? HomeUiState.Info)?.let { lastInfo = it }
        if (current is HomeUiState.Idle) lastInfo = null
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
                onClick = { viewModel.startDownload(onDownloadStarted) },
                onReset = { viewModel.resetScreen() }
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
 * ytdlnis style: spans nearly the whole screen (96% of its width, 78%
 * of its height in portrait, 92% in landscape) and the monospace
 * command preview fills all the free space instead of a small box.
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
    // Landscape phones are short: give the dialog more of the height
    // so the input field and the buttons never get squeezed out.
    val config = LocalConfiguration.current
    val heightFraction =
        if (config.screenHeightDp > config.screenWidthDp) 0.78f else 0.92f
    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false)
    ) {
        Surface(
            modifier = Modifier
                .fillMaxWidth(0.96f)
                .fillMaxHeight(heightFraction),
            shape = MaterialTheme.shapes.extraLarge,
            color = MaterialTheme.colorScheme.surfaceContainerHigh
        ) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(20.dp)
            ) {
                Text(
                    text = "Extra commands",
                    style = MaterialTheme.typography.headlineSmall
                )
                Spacer(Modifier.height(6.dp))
                Text(
                    "The exact command that will run:",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Spacer(Modifier.height(10.dp))
                Surface(
                    modifier = Modifier
                        .fillMaxWidth()
                        .weight(1f),
                    shape = MaterialTheme.shapes.small,
                    color = MaterialTheme.colorScheme.surfaceContainerHighest
                ) {
                    Column(
                        modifier = Modifier
                            .fillMaxSize()
                            .verticalScroll(rememberScrollState())
                            .padding(12.dp)
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
                Spacer(Modifier.height(14.dp))
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
                Spacer(Modifier.height(10.dp))
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.End
                ) {
                    TextButton(onClick = onDismiss) { Text("Cancel") }
                    Spacer(Modifier.width(8.dp))
                    TextButton(onClick = { onConfirm(text) }) { Text("Done") }
                }
            }
        }
    }
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

/**
 * Sticky bar pinned above the bottom navigation while formats are
 * shown. Left of the Download button sits a square 1:1 reset button:
 * same height, same rounded shape, softer tonal color so Download
 * stays the primary action. One tap wipes the loaded link, formats
 * and selections and brings the big circular button back.
 */
@Composable
private fun StickyDownloadBar(
    enabled: Boolean,
    sizeBytes: Long?,
    videoOnly: Boolean,
    onClick: () -> Unit,
    onReset: () -> Unit
) {
    val style = rememberBigButtonStyle()
    val config = LocalConfiguration.current
    val subtitleFontSize = (config.screenWidthDp * 0.036f).coerceIn(12f, 15f).sp
    Surface(
        modifier = Modifier.fillMaxWidth(),
        color = MaterialTheme.colorScheme.surfaceContainer,
        tonalElevation = 3.dp
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(start = 16.dp, end = 16.dp, top = 12.dp, bottom = 12.dp)
        ) {
            FilledTonalIconButton(
                onClick = onReset,
                modifier = Modifier.size(style.height),
                shape = MaterialTheme.shapes.large
            ) {
                Icon(
                    imageVector = Icons.Rounded.Close,
                    contentDescription = "Clear the current link",
                    modifier = Modifier.size(style.height * 0.45f)
                )
            }
            Spacer(Modifier.width(12.dp))
            Button(
                onClick = onClick,
                enabled = enabled,
                modifier = Modifier
                    .weight(1f)
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
FFMUX_EOF_HOME11
cat > "$STAGE/ui/home/HomeViewModel.kt" <<'FFMUX_EOF_VM11'
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
import com.ffmux.app.engine.FormatSections
import com.ffmux.app.engine.VideoInfo
import com.ffmux.app.engine.YtDlpEngine
import kotlinx.coroutines.launch

sealed interface HomeUiState {
    data object Idle : HomeUiState
    data object Loading : HomeUiState
    data class Error(val message: String) : HomeUiState
    data class Info(
        val fetchedUrl: String,
        val info: VideoInfo,
        val sections: FormatSections
    ) : HomeUiState
}

/**
 * Home screen state holder. The URL, the fetched video info and the
 * quality selections SURVIVE starting a download and switching tabs:
 * nothing is reset when a download is queued, so coming back from the
 * Downloads tab shows the same video and picks again. The square
 * button left of the Download bar calls resetScreen() to wipe all of
 * it on demand and return to the empty start page.
 */
class HomeViewModel(application: Application) : AndroidViewModel(application) {

    var url by mutableStateOf("")
        private set
    var state by mutableStateOf<HomeUiState>(HomeUiState.Idle)
        private set

    /**
     * Bumped by every fetch() and by resetScreen(). A fetch only
     * stores its result while the generation still matches, so the
     * info of a link the user already cleared never pops back in.
     */
    private var fetchGeneration = 0

    /** True while the "Best" shortcut card is the active selection. */
    var bestSelected by mutableStateOf(true)
        private set

    /** Index into HomeUiState.Info.sections.video, -1 = none. */
    var selectedVideo by mutableStateOf(-1)
        private set

    /** Index into HomeUiState.Info.sections.audio, -1 = none. */
    var selectedAudio by mutableStateOf(-1)
        private set

    var editableTitle by mutableStateOf("")
        private set
    var editableUploader by mutableStateOf("")
        private set

    /** yt-dlp extras picked under the quality cards (ytdlnis style). */
    var embedThumbnail by mutableStateOf(false)
        private set
    var embedMetadata by mutableStateOf(false)
        private set
    var splitChapters by mutableStateOf(false)
        private set

    /** Download straight to the final name, no .part files (--no-part). */
    var noPart by mutableStateOf(false)
        private set

    /** Recording time limit in minutes, 0 = unlimited (live streams). */
    var recordMinutes by mutableStateOf(0)
        private set

    /** Extra yt-dlp arguments from the "Extra commands" dialog. */
    var extraArgs by mutableStateOf("")
        private set

    /** Selected subtitle languages (yt-dlp codes), empty = no subtitles. */
    var subLangs by mutableStateOf(setOf<String>())
        private set

    fun updateTitle(value: String) {
        editableTitle = value
    }

    fun updateUploader(value: String) {
        editableUploader = value
    }

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

    /**
     * Wipes the fetched link, video info, formats, selections and the
     * per-link recording limit and returns to the empty start page
     * with the big circular button. The option chips keep their
     * values: they are user preferences, not per-link state. A fetch
     * that is still running is dropped by its generation; downloads
     * already sitting in the queue are NOT touched.
     */
    fun resetScreen() {
        fetchGeneration++
        url = ""
        state = HomeUiState.Idle
        bestSelected = true
        selectedVideo = -1
        selectedAudio = -1
        editableTitle = ""
        editableUploader = ""
        recordMinutes = 0
    }

    fun toggleEmbedThumbnail() {
        embedThumbnail = !embedThumbnail
    }

    fun toggleEmbedMetadata() {
        embedMetadata = !embedMetadata
    }

    fun toggleSplitChapters() {
        splitChapters = !splitChapters
    }

    fun toggleNoPart() {
        noPart = !noPart
    }

    fun updateRecordMinutes(value: Int) {
        recordMinutes = value.coerceIn(0, 1440)
    }

    fun updateExtraArgs(value: String) {
        extraArgs = value
    }

    fun updateSubLangs(langs: Set<String>) {
        subLangs = langs
    }

    /**
     * Extra yt-dlp arguments for the option chips only, as one space
     * separated "--flag value" string. Used by the command preview.
     */
    fun baseDownloadArgs(): String {
        val args = mutableListOf<String>()
        if (embedThumbnail) {
            args.add("--embed-thumbnail")
            args.add("--convert-thumbnails")
            args.add("jpg")
        }
        if (subLangs.isNotEmpty()) {
            args.add("--embed-subs")
            args.add("--sub-langs")
            args.add(subLangs.sorted().joinToString(","))
        }
        if (embedMetadata) args.add("--embed-metadata")
        if (splitChapters) args.add("--split-chapters")
        if (noPart) args.add("--no-part")
        return args.joinToString(" ")
    }

    /**
     * Everything the engine receives: the option chips plus the extra
     * arguments from the "Extra commands" dialog. Parsed back by the
     * engine right before the download runs, so the chosen flags travel
     * inside the queue entity and survive app restarts.
     */
    fun buildDownloadArgs(): String {
        val base = baseDownloadArgs()
        val extra = extraArgs
            .replace(Regex("[\\r\\n\\t]+"), " ")
            .trim()
            .split(Regex("\\s+"))
            .filter { it.isNotBlank() }
        val parts = mutableListOf<String>()
        if (base.isNotBlank()) parts.add(base)
        parts.addAll(extra)
        return parts.joinToString(" ")
    }

    fun selectBest() {
        bestSelected = true
        selectedVideo = -1
        selectedAudio = -1
    }

    fun toggleVideo(index: Int) {
        bestSelected = false
        selectedVideo = if (selectedVideo == index) -1 else index
    }

    fun toggleAudio(index: Int) {
        bestSelected = false
        selectedAudio = if (selectedAudio == index) -1 else index
    }

    fun fetch() {
        val target = url.trim()
        if (target.isBlank()) return
        val generation = ++fetchGeneration
        state = HomeUiState.Loading
        viewModelScope.launch {
            try {
                Graph.awaitEngine()
                val info = Graph.engine.fetchInfo(target)
                if (info.type == "playlist") {
                    if (generation == fetchGeneration) {
                        state = HomeUiState.Error("Playlist links are not supported yet.")
                    }
                    return@launch
                }
                val sections = YtDlpEngine.buildFormatSections(info)
                if (sections.video.isEmpty() && sections.audio.isEmpty()) {
                    if (generation == fetchGeneration) {
                        state = HomeUiState.Error("No downloadable formats found.")
                    }
                    return@launch
                }
                if (generation != fetchGeneration) return@launch
                bestSelected = true
                selectedVideo = -1
                selectedAudio = -1
                editableTitle = info.title ?: "Untitled"
                editableUploader = info.uploader ?: ""
                state = HomeUiState.Info(fetchedUrl = target, info = info, sections = sections)
            } catch (e: Exception) {
                if (generation == fetchGeneration) {
                    state = HomeUiState.Error((e.message ?: "Could not fetch video info.").take(300))
                }
            }
        }
    }

    /** The yt-dlp format selector for the current selection, or null. */
    fun selectedSelector(): String? {
        val current = state as? HomeUiState.Info ?: return null
        val video = current.sections.video.getOrNull(selectedVideo)
        val audio = current.sections.audio.getOrNull(selectedAudio)
        return when {
            bestSelected -> current.sections.best.selector
            video != null && audio != null -> "${video.selector}+${audio.selector}"
            video != null -> video.selector
            audio != null -> audio.selector
            else -> null
        }
    }

    /** True when a video-only stream is picked without any audio stream. */
    fun isVideoOnlySelection(): Boolean {
        if (bestSelected) return false
        val current = state as? HomeUiState.Info ?: return false
        return selectedVideo >= 0 && selectedAudio < 0 && current.sections.video.isNotEmpty()
    }

    /** Short label of the current selection, shown in the Downloads list. */
    fun selectedLabel(): String {
        val current = state as? HomeUiState.Info ?: return ""
        val video = current.sections.video.getOrNull(selectedVideo)
        val audio = current.sections.audio.getOrNull(selectedAudio)
        return when {
            bestSelected -> "Best"
            video != null && audio != null -> "${video.label} + ${audio.label}"
            video != null -> "${video.label} (video only)"
            audio != null -> audio.label
            else -> ""
        }
    }

    /** Estimated byte size of the resulting file, or null when unknown. */
    fun selectedSizeBytes(): Long? {
        val current = state as? HomeUiState.Info ?: return null
        val video = current.sections.video.getOrNull(selectedVideo)
        val audio = current.sections.audio.getOrNull(selectedAudio)
        return when {
            bestSelected -> current.sections.best.sizeBytes
            video != null && audio != null ->
                if (video.sizeBytes != null && audio.sizeBytes != null) {
                    video.sizeBytes!! + audio.sizeBytes!!
                } else {
                    video.sizeBytes ?: audio.sizeBytes
                }
            video != null -> video.sizeBytes
            audio != null -> audio.sizeBytes
            else -> null
        }
    }

    fun startDownload(onQueued: () -> Unit) {
        val current = state as? HomeUiState.Info ?: return
        val selector = selectedSelector() ?: return
        val info = current.info
        // The link that was actually FETCHED, not the live text field:
        // clearing or editing the field after fetching must not break
        // (or silently retarget) the download.
        val target = current.fetchedUrl
        val label = selectedLabel().ifBlank { "Best" }

        viewModelScope.launch {
            val entity = DownloadEntity(
                url = target,
                title = editableTitle.ifBlank { info.title ?: "Untitled" },
                thumbnail = info.thumbnail,
                uploader = editableUploader.ifBlank { info.uploader },
                durationSec = info.duration,
                formatSelector = selector,
                formatLabel = label,
                downloadArgs = buildDownloadArgs(),
                recordMinutes = recordMinutes,
                createdAt = System.currentTimeMillis()
            )
            Graph.db.downloadDao().insert(entity)
            DownloadService.start(getApplication())
            // Intentionally NOT clearing url / state / selections here:
            // the user asked for the previous link and formats to stay.
            onQueued()
        }
    }
}
FFMUX_EOF_VM11

# --- Install the complete sources (content-stable, idempotent). --------------
install_if_needed() {
    if cmp -s "$1" "$2"; then
        echo "  [skip] $2 is already up to date"
    else
        install -m 644 "$1" "$2"
        echo "  [ok] updated $2"
    fi
}
install_if_needed "$STAGE/ui/home/HomeScreen.kt"    "$HOME_KT"
install_if_needed "$STAGE/ui/home/HomeViewModel.kt" "$VM_KT"

# --- Version bump: -> 1.4.4 (versionCode 11). --------------------------------
if grep -qF 'versionName = "1.4.4"' "$BUILD_G" && grep -qF 'versionCode = 11' "$BUILD_G"; then
    echo "  [skip] version is already 1.4.4 (versionCode 11)"
else
    sed -i -E 's/versionCode = [0-9]+/versionCode = 11/' "$BUILD_G"
    sed -i -E 's/versionName = "[^"]+"/versionName = "1.4.4"/' "$BUILD_G"
    grep -qF 'versionCode = 11' "$BUILD_G" || { echo "FATAL: versionCode bump failed"; exit 1; }
    grep -qF 'versionName = "1.4.4"' "$BUILD_G" || { echo "FATAL: versionName bump failed"; exit 1; }
    echo "  [ok] version -> 1.4.4 (versionCode 11)"
fi

# --- Final verification. ------------------------------------------------------
verify() {
    if ! grep -qF "$2" "$1"; then
        echo "FATAL: $1 does not contain: $2"
        exit 1
    fi
}
verify "$HOME_KT"  'package com.ffmux.app.ui.home'
verify "$HOME_KT"  'rememberBigButtonStyle'
verify "$HOME_KT"  'FilledTonalIconButton'
verify "$HOME_KT"  'Icons.Rounded.Close'
verify "$HOME_KT"  'onReset = { viewModel.resetScreen() }'
verify "$HOME_KT"  'if (current is HomeUiState.Idle) lastInfo = null'
verify "$HOME_KT"  'DialogProperties(usePlatformDefaultWidth = false)'
verify "$HOME_KT"  'fillMaxWidth(0.96f)'
verify "$HOME_KT"  'ExtraCommandsDialog'
verify "$HOME_KT"  'buildCommandPreview'
verify "$HOME_KT"  'screenWidthDp * 0.5f'
verify "$HOME_KT"  '\u2248'
verify "$VM_KT"    'package com.ffmux.app.ui.home'
verify "$VM_KT"    'fun resetScreen()'
verify "$VM_KT"    'fetchGeneration'
verify "$VM_KT"    'recordMinutes'
verify "$BUILD_G"  'versionCode = 11'
verify "$BUILD_G"  'versionName = "1.4.4"'
echo "== FFMux patch 11 applied: v1.4.4 (versionCode 11) =="
