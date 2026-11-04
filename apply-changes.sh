#!/usr/bin/env bash
###############################################################################
# FFMux patch 13 (v1.4.6) -- verified surgical patch.
# Run from the repository root:  bash apply-changes.sh
#
# Safety design (different from patches 10-12, same guarantee):
#   * the exact input state is verified with sha256 BEFORE anything is
#     touched -- if the tree is not the expected base, the script fails
#     loudly instead of patching something unknown,
#   * all replacements are applied in one python3 pass that only writes
#     the files after every single anchor matched exactly once,
#   * the exact output state is verified with sha256 afterwards,
#   * running it again on a patched tree is a clean no-op.
#
# NOTE: v1.4.5 (patch 12) was accidentally overwritten on Nov 4 by a
# re-upload of the older patch 11 (v1.4.4); this patch restores the
# parts of patch 12 that matter (metadata default, red X, button
# feedback, recording-limit wording) and builds on top of them.
#
# What is new (patch 13), on top of everything from patches 1-12:
#   1. Filename template picker (ytdlnis style): the pencil is now a
#      real, square 1:1 button at the right end of the Author row
#      (exactly the Author field height), no longer a dead icon inside
#      the Title field. It opens a near-full-screen dialog listing the
#      yt-dlp output-template fields (Title, Video ID, Uploader,
#      Channel, Upload date, Duration, Resolution, Height, Format ID,
#      Views, Likes, Language) as checkboxes; the "Saved as" preview
#      updates live and fills the known fields with the real values of
#      this video. Title and Author stay directly editable in the card.
#   2. Metadata chip: ON by default again, and every newly fetched
#      link starts from that default.
#   3. The reset X next to Download is solid red (Material red 700,
#      #D32F2F) with a white icon.
#   4. Press feedback on the main action buttons -- the big circular
#      fetch button, "Get quality", the sticky Download button, the
#      reset X and the pencil: while the finger is down the button
#      shrinks to 85% of its size, on release it springs back, the
#      same feel as the bottom navigation tabs. (The old pulse never
#      showed because its scale was read in the wrong recompose scope;
#      the scale now lives in the draw layer.)
#   5. Download file names: the engine keeps the "%(" of template
#      fields intact, drops a field cut in half by the length limit
#      and a duplicate ".%(ext)s" suffix, and the command preview
#      shows 80 characters of the template.
#
# App version after this script: 1.4.6 (versionCode 13 -- code 12 was
# used by v1.4.5, so 13 keeps every installed build upgradable).
#
# Base verified by this script: the tree produced by patch 11
# (v1.4.4, versionCode 11, commit 85816fa).
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
BUILD_G="app/build.gradle.kts"

for f in "$HOME_KT" "$VM_KT" "$SVC_KT" "$BUILD_G"; do
    if [ ! -f "$f" ]; then
        echo "FATAL: $f not found - run from the repository root"
        exit 1
    fi
done

# --- sha256 of the expected OUTPUT (patched) tree ------------------------------
OUT_HASHES='c3775fd7f987c6b3e8b136b269c7554590be451569158a7df60d321bd05ae827  app/src/main/java/com/ffmux/app/ui/home/HomeScreen.kt
1abce1334a0b86761921a8ea3db1883f8aa7deceaddf274c422d00a798d93905  app/src/main/java/com/ffmux/app/ui/home/HomeViewModel.kt
2a48c4f1a6a2ccecaa9df891f0c7e09c6230ecd3ce3979fb1dc7ce51bbd06af9  app/src/main/java/com/ffmux/app/engine/DownloadService.kt'

output_matches() {
    printf '%s\n' "$OUT_HASHES" | (cd "$(dirname "$0")" && sha256sum -c --status -) 2>/dev/null
}

# --- sha256 of the expected INPUT (v1.4.4 base) tree ---------------------------
BASE_HASHES='1a8bb0920fc737f25650bc4ed9c2596514c43753755d7fb1e7dedf4c0c7fe5a1  app/src/main/java/com/ffmux/app/ui/home/HomeScreen.kt
e8a1e75d033244c5c4b8ace13754352c91ff1479768bc312dc73cb5b10b5c0c1  app/src/main/java/com/ffmux/app/ui/home/HomeViewModel.kt
8519d4565e0441f74a355890d36df8fc41ee6780e2c7e0ca0c536d079fa7fc94  app/src/main/java/com/ffmux/app/engine/DownloadService.kt'

base_matches() {
    printf '%s\n' "$BASE_HASHES" | (cd "$(dirname "$0")" && sha256sum -c --status -) 2>/dev/null
}

if output_matches; then
    echo "  [skip] sources are already patched (v1.4.6 tree detected)"
else
    if ! base_matches; then
        echo "FATAL: the source files are neither the expected v1.4.4 base"
        echo "       nor the patched v1.4.6 tree. Another patch version seems"
        echo "       to have been applied in between -- do not force this."
        exit 1
    fi
    echo "  [ok] base state verified (exact v1.4.4 tree, sha256)"

    python3 - <<'PYEOF'
import sys

PATCHES = [
    # (path, [(old, new), ...])
    (r'''app/src/main/java/com/ffmux/app/ui/home/HomeScreen.kt''', [
        (r'''
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
''',
         r'''
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.IntrinsicSize
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
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
'''),
        (r'''import androidx.compose.material3.ElevatedCard
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
''',
         r'''import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
'''),
        (r'''import androidx.compose.runtime.remember
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
''',
         r'''import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.graphicsLayer
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.text.font.FontFamily
'''),
        (r'''                            url = (viewModel.state as? HomeUiState.Info)?.fetchedUrl
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
''',
         r'''                            url = (viewModel.state as? HomeUiState.Info)?.fetchedUrl
                                ?: viewModel.url,
                            title = viewModel.editableTitle
                        )
                    },
                    durationNote = if (viewModel.recordMinutes > 0) {
                        "stops ${durationText(viewModel.recordMinutes)} after the recording starts (enforced by FFMux)"
                    } else {
                        null
                    }
                )
                Spacer(Modifier.height(8.dp))
            }
'''),
        (r'''    onClick: () -> Unit
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
''',
         r'''    onClick: () -> Unit
) {
    Box(
        modifier = Modifier.fillMaxWidth(),
        contentAlignment = Alignment.Center
    ) {
        val interactionSource = remember { MutableInteractionSource() }
        FilledIconButton(
            onClick = onClick,
            enabled = !loading,
            interactionSource = interactionSource,
            modifier = rememberPressScale(interactionSource)
                .size((LocalConfiguration.current.screenWidthDp * 0.5f).dp),
            shape = androidx.compose.foundation.shape.CircleShape
        ) {
            if (loading) {
                CircularProgressIndicator(
                    modifier = Modifier.size((LocalConfiguration.current.screenWidthDp * 0.20f).dp),
                    strokeWidth = (LocalConfiguration.current.screenWidthDp * 0.015f).dp,
'''),
        (r'''@Composable
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
''',
         r'''@Composable
private fun HorizontalFetchButton(
    loading: Boolean,
    onClick: () -> Unit
) {
    val style = rememberBigButtonStyle()
    val interactionSource = remember { MutableInteractionSource() }
    Button(
        onClick = onClick,
        enabled = !loading,
        interactionSource = interactionSource,
        modifier = rememberPressScale(interactionSource)
            .fillMaxWidth()
            .height(style.height),
        shape = MaterialTheme.shapes.large
    ) {
        if (loading) {
            CircularProgressIndicator(
'''),
        (r'''    return BigButtonStyle(
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
''',
         r'''    return BigButtonStyle(
        height = (config.screenWidthDp * 0.14f).coerceIn(48f, 64f).dp,
        fontSize = (config.screenWidthDp * 0.05f).coerceIn(17f, 21f).sp
    )
}

/**
 * Press feedback shared by the main action buttons (the big circular
 * fetch button, "Get quality", the sticky Download button, the reset
 * X and the template pencil): while the finger is down the button
 * shrinks to 85% of its size, on release it springs back -- the same
 * feel as the tabs on the bottom navigation bar. The scale is read
 * inside the graphics layer block, so it animates during the draw
 * phase and every button updates without recomposing its parent.
 */
@Composable
private fun rememberPressScale(interactionSource: MutableInteractionSource): Modifier {
    val pressed by interactionSource.collectIsPressedAsState()
    val scale by animateFloatAsState(
        targetValue = if (pressed) 0.85f else 1f,
        animationSpec = spring(
            dampingRatio = Spring.DampingRatioMediumBouncy,
            stiffness = Spring.StiffnessMedium
        ),
        label = "pressScale"
    )
    return Modifier.graphicsLayer {
        scaleX = scale
        scaleY = scale
    }
}

/**
 * Chip with a dropdown arrow for the recording time limit: the left
 * side shows the chosen time (or "Duration" when off), the arrow on
 * the right opens the picker -- exactly like ( 2m | v ).
 */
@Composable
'''),
        (r'''    title: String
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
''',
         r'''    title: String
): String {
    val parts = mutableListOf("yt-dlp", "--no-playlist")
    parts.add("-f")
    parts.add(selector ?: "bestvideo*+bestaudio/best")
    parts.add("-o")
    parts.add("\"${title.trim().ifBlank { "Untitled" }.take(80)}.%(ext)s\"")
    parts.add("--no-mtime")
    parts.add("--retries")
    parts.add("10")
    parts.add("--fragment-retries")
    parts.add("10")
    parts.add("--socket-timeout")
'''),
        (r'''    info: VideoInfo,
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
''',
         r'''    info: VideoInfo,
    title: String,
    onTitleChange: (String) -> Unit,
    uploader: String,
    onUploaderChange: (String) -> Unit
) {
    var showTemplate by rememberSaveable { mutableStateOf(false) }
    ElevatedCard(
        modifier = Modifier.fillMaxWidth(),
        shape = MaterialTheme.shapes.small
    ) {
        Column {
            Box(Modifier.fillMaxWidth()) {
'''),
        (r'''                    value = title,
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
''',
         r'''                    value = title,
                    onValueChange = onTitleChange,
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("Title") },
                    singleLine = true,
                    textStyle = MaterialTheme.typography.titleMedium,
                    shape = MaterialTheme.shapes.small
                )
                Spacer(Modifier.height(8.dp))
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(IntrinsicSize.Min),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    OutlinedTextField(
                        value = uploader,
                        onValueChange = onUploaderChange,
                        modifier = Modifier
                            .weight(1f)
                            .fillMaxHeight(),
                        label = { Text("Author") },
                        singleLine = true,
                        textStyle = MaterialTheme.typography.bodyMedium,
                        shape = MaterialTheme.shapes.small
                    )
                    Spacer(Modifier.width(8.dp))
                    val pencilInteraction = remember { MutableInteractionSource() }
                    FilledTonalIconButton(
                        onClick = { showTemplate = true },
                        interactionSource = pencilInteraction,
                        modifier = rememberPressScale(pencilInteraction)
                            .fillMaxHeight()
                            .aspectRatio(1f),
                        shape = MaterialTheme.shapes.small
                    ) {
                        Icon(
                            imageVector = Icons.Outlined.Edit,
                            contentDescription = "Filename template"
                        )
                    }
                }
            }
        }
    }
    if (showTemplate) {
        FilenameTemplateDialog(
            info = info,
            initialTemplate = title,
            onDismiss = { showTemplate = false },
            onConfirm = { newTemplate ->
                onTitleChange(newTemplate)
                showTemplate = false
            }
        )
    }
}

/** One yt-dlp output template field offered in the picker dialog. */
private data class TemplateToken(
    val token: String,
    val label: String,
    val hint: String
)

/** yt-dlp "output template" naming fields, ytdlnis style. */
private val templateTokens = listOf(
    TemplateToken("%(title)s", "Title", "the title of the video"),
    TemplateToken("%(id)s", "Video ID", "the id used by the site"),
    TemplateToken("%(uploader)s", "Uploader", "the author of the video"),
    TemplateToken("%(channel)s", "Channel", "the channel name"),
    TemplateToken("%(upload_date)s", "Upload date", "upload date, YYYYMMDD"),
    TemplateToken("%(duration)s", "Duration", "length in seconds"),
    TemplateToken("%(resolution)s", "Resolution", "like 1920x1080"),
    TemplateToken("%(height)s", "Height", "like 1080"),
    TemplateToken("%(format_id)s", "Format ID", "the picked quality"),
    TemplateToken("%(view_count)s", "Views", "the view count"),
    TemplateToken("%(like_count)s", "Likes", "the like count"),
    TemplateToken("%(language)s", "Language", "the audio language")
)

/**
 * Pencil dialog of the info card: the yt-dlp output template fields
 * can be toggled on and off, every change updates the "Saved as"
 * preview right away, and plain typed text simply stays in the name.
 * The extension is appended by the engine when the file is saved.
 */
@Composable
private fun FilenameTemplateDialog(
    info: VideoInfo,
    initialTemplate: String,
    onDismiss: () -> Unit,
    onConfirm: (String) -> Unit
) {
    var text by remember { mutableStateOf(initialTemplate) }
    // Landscape phones are short: give the dialog more of the height
    // so the input field and the buttons never get squeezed out.
    val config = LocalConfiguration.current
    val heightFraction =
        if (config.screenHeightDp > config.screenWidthDp) 0.78f else 0.92f

    fun toggleToken(token: String) {
        text = if (token in text) {
            text.replace(token, "")
                .replace(Regex("\\s{2,}"), " ")
                .trim()
        } else if (text.isBlank()) {
            token
        } else {
            text.trim() + " " + token
        }
    }

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
                    text = "Filename template",
                    style = MaterialTheme.typography.headlineSmall
                )
                Spacer(Modifier.height(6.dp))
                Text(
                    "Toggle the yt-dlp naming fields to build the file " +
                        "name. Anything you type stays as plain text, " +
                        "yt-dlp fills the fields in when the file is " +
                        "saved and the extension is added automatically.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Spacer(Modifier.height(12.dp))
                OutlinedTextField(
                    value = text,
                    onValueChange = { text = it },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("File name") },
                    singleLine = true,
                    textStyle = MaterialTheme.typography.titleMedium,
                    shape = MaterialTheme.shapes.small
                )
                Spacer(Modifier.height(12.dp))
                Text(
                    "Output template fields",
                    style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Spacer(Modifier.height(4.dp))
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
                            .padding(horizontal = 6.dp, vertical = 2.dp)
                    ) {
                        templateTokens.forEach { entry ->
                            val checked = entry.token in text
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clip(MaterialTheme.shapes.extraSmall)
                                    .selectable(
                                        selected = checked,
                                        onClick = { toggleToken(entry.token) }
                                    )
                                    .padding(vertical = 2.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Checkbox(
                                    checked = checked,
                                    onCheckedChange = { toggleToken(entry.token) }
                                )
                                Column(
                                    modifier = Modifier.weight(1f),
                                    horizontalAlignment = Alignment.Start
                                ) {
                                    Text(
                                        text = entry.label,
                                        style = MaterialTheme.typography.bodyLarge
                                    )
                                    Text(
                                        text = entry.hint,
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                }
                                Text(
                                    text = entry.token,
                                    style = MaterialTheme.typography.bodySmall.copy(
                                        fontFamily = FontFamily.Monospace
                                    ),
                                    color = MaterialTheme.colorScheme.primary
                                )
                            }
                        }
                    }
                }
                Spacer(Modifier.height(12.dp))
                Surface(
                    modifier = Modifier.fillMaxWidth(),
                    shape = MaterialTheme.shapes.small,
                    color = MaterialTheme.colorScheme.surfaceContainerHighest
                ) {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(10.dp)
                    ) {
                        Text(
                            text = "Saved as",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        Text(
                            text = previewFileName(text, info),
                            style = MaterialTheme.typography.bodySmall.copy(
                                fontFamily = FontFamily.Monospace,
                                lineHeight = 16.sp
                            ),
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis
                        )
                    }
                }
                Spacer(Modifier.height(10.dp))
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    TextButton(onClick = { text = info.title ?: "" }) {
                        Text("Use original")
                    }
                    Spacer(Modifier.weight(1f))
                    TextButton(onClick = onDismiss) { Text("Cancel") }
                    TextButton(onClick = { onConfirm(text) }) { Text("Done") }
                }
            }
        }
    }
}

/**
 * The "Saved as" preview: the fields this video already knows are
 * filled with their real values, the others stay visible as template
 * text so it is clear yt-dlp will fill them in at save time.
 */
private fun previewFileName(template: String, info: VideoInfo): String {
    var name = template.trim()
    if (name.isEmpty()) name = info.title ?: "Untitled"
    info.title?.let { name = name.replace("%(title)s", it) }
    info.id?.let { name = name.replace("%(id)s", it) }
    info.uploader?.let {
        name = name.replace("%(uploader)s", it)
        name = name.replace("%(channel)s", it)
    }
    info.duration?.let { name = name.replace("%(duration)s", it.toString()) }
    name = name.replace("%(ext)s", "mp4")
    return name
}

/** Full-width shortcut card for the combined best video + audio format. */
@Composable
private fun BestCard(
    option: FormatOption,
    selected: Boolean,
    onClick: () -> Unit
'''),
        (r'''    }
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
''',
         r'''    }
}

/**
 * Sticky bar pinned above the bottom navigation while formats are
 * shown. Left of the Download button sits a square 1:1 reset button:
 * same height, same rounded shape, solid red so it reads as the
 * destructive "start over" action. One tap wipes the loaded link,
 * formats and selections and brings the big circular button back.
 */
@Composable
private fun StickyDownloadBar(
    enabled: Boolean,
    sizeBytes: Long?,
    videoOnly: Boolean,
'''),
        (r'''    ) {
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
''',
         r'''    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(start = 16.dp, end = 16.dp, top = 12.dp, bottom = 12.dp)
        ) {
            val resetInteraction = remember { MutableInteractionSource() }
            FilledTonalIconButton(
                onClick = onReset,
                interactionSource = resetInteraction,
                modifier = rememberPressScale(resetInteraction)
                    .size(style.height),
                shape = MaterialTheme.shapes.large,
                colors = IconButtonDefaults.filledTonalIconButtonColors(
                    containerColor = Color(0xFFD32F2F),
                    contentColor = Color(0xFFFFFFFF)
                )
            ) {
                Icon(
                    imageVector = Icons.Rounded.Close,
                    contentDescription = "Clear the current link",
                    modifier = Modifier.size(style.height * 0.45f)
                )
            }
            Spacer(Modifier.width(12.dp))
            val downloadInteraction = remember { MutableInteractionSource() }
            Button(
                onClick = onClick,
                enabled = enabled,
                interactionSource = downloadInteraction,
                modifier = rememberPressScale(downloadInteraction)
                    .weight(1f)
                    .height(style.height),
                shape = MaterialTheme.shapes.large
            ) {
                // Single line: title and approximate size side by side.
                Text(
'''),
    ]),
    (r'''app/src/main/java/com/ffmux/app/ui/home/HomeViewModel.kt''', [
        (r'''    var editableUploader by mutableStateOf("")
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
''',
         r'''    var editableUploader by mutableStateOf("")
        private set

    /** yt-dlp extras picked under the quality cards (ytdlnis style). */
    var embedThumbnail by mutableStateOf(false)
        private set

    /**
     * Metadata is wanted for essentially every download, so the chip
     * is ON by default and every newly fetched link starts from that
     * default again. It can still be turned off for a clean file.
     */
    var embedMetadata by mutableStateOf(true)
        private set
    var splitChapters by mutableStateOf(false)
        private set

    /** Download straight to the final name, no .part files (--no-part). */
    var noPart by mutableStateOf(false)
'''),
        (r'''                if (generation != fetchGeneration) return@launch
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
''',
         r'''                if (generation != fetchGeneration) return@launch
                bestSelected = true
                selectedVideo = -1
                selectedAudio = -1
                editableTitle = info.title ?: "Untitled"
                editableUploader = info.uploader ?: ""
                // Every new link starts from the default: metadata on.
                embedMetadata = true
                state = HomeUiState.Info(fetchedUrl = target, info = info, sections = sections)
            } catch (e: Exception) {
                if (generation == fetchGeneration) {
                    state = HomeUiState.Error((e.message ?: "Could not fetch video info.").take(300))
                }
            }
'''),
    ]),
    (r'''app/src/main/java/com/ffmux/app/engine/DownloadService.kt''', [
        (r'''        Graph.clearLog(item.id)
        Graph.updateByteProgress(item.id, null)
        val argsLine = if (item.downloadArgs.isBlank()) "" else " ${item.downloadArgs}"
        Graph.appendLog(item.id, "\$ yt-dlp -f ${item.formatSelector}$argsLine")
        Graph.appendLog(item.id, "\$ url: ${item.url}")
        val tempDir = File(cacheDir, "downloads/${item.id}").apply { mkdirs() }
        val safeTitle = item.title
            .replace(Regex("[\\/:*?\"<>|%]"), "_")
            .trim()
            .take(80)
            .ifEmpty { "Untitled" }
        val template = "${tempDir.absolutePath}/$safeTitle.%(ext)s"

        updateNotification(item.title, "Starting...", 0)

        // Recording time limit (live streams): stop the process this many
''',
         r'''        Graph.clearLog(item.id)
        Graph.updateByteProgress(item.id, null)
        val argsLine = if (item.downloadArgs.isBlank()) "" else " ${item.downloadArgs}"
        Graph.appendLog(item.id, "\$ yt-dlp -f ${item.formatSelector}$argsLine")
        Graph.appendLog(item.id, "\$ url: ${item.url}")
        val tempDir = File(cacheDir, "downloads/${item.id}").apply { mkdirs() }
        // The title can carry yt-dlp output-template fields ("%(title)s",
        // "%(id)s", ...) picked in the Filename template dialog. A "%"
        // that opens a field must survive; only a stray one is replaced
        // with "_". A field cut in half by the length limit and a
        // manual ".%(ext)s" suffix (added below anyway) are dropped, so
        // the template that reaches yt-dlp is always valid.
        val safeTitle = item.title
            .replace(Regex("[\\/:*?\"<>|]"), "_")
            .replace(Regex("%(?!\\()"), "_")
            .trim()
            .take(120)
            .replace(Regex("%\\([a-zA-Z0-9_.]*\\)?$"), "")
            .trim()
            .trimEnd('.', ' ', '-')
            .ifEmpty { "Untitled" }
        val template = "${tempDir.absolutePath}/$safeTitle.%(ext)s"

        updateNotification(item.title, "Starting...", 0)

        // Recording time limit (live streams): stop the process this many
'''),
    ]),
]

results = []
for path, pairs in PATCHES:
    with open(path, encoding="utf-8") as f:
        src = f.read()
    for i, (old, new) in enumerate(pairs):
        n = src.count(old)
        if n != 1:
            print("FATAL: %s hunk #%d matches %dx" % (path, i, n))
            sys.exit(1)
        src = src.replace(old, new, 1)
    results.append((path, src))
# everything matched -- write all files now (atomic-ish: no partial
# replacement is ever written)
for path, src in results:
    with open(path, "w", encoding="utf-8") as f:
        f.write(src)
    print("  [ok] patched " + path)

PYEOF

    printf '%s\n' "$OUT_HASHES" | sha256sum -c --status || {
        echo "FATAL: patched files do not match the verified v1.4.6 tree"
        exit 1
    }
    echo "  [ok] patched tree verified (exact v1.4.6 tree, sha256)"
fi

# --- Version bump: -> 1.4.6 (versionCode 13). --------------------------------
if grep -qF 'versionName = "1.4.6"' "$BUILD_G" && grep -qF 'versionCode = 13' "$BUILD_G"; then
    echo "  [skip] version is already 1.4.6 (versionCode 13)"
else
    sed -i -E 's/versionCode = [0-9]+/versionCode = 13/' "$BUILD_G"
    sed -i -E 's/versionName = "[^"]+"/versionName = "1.4.6"/' "$BUILD_G"
    grep -qF 'versionCode = 13' "$BUILD_G" || { echo "FATAL: versionCode bump failed"; exit 1; }
    grep -qF 'versionName = "1.4.6"' "$BUILD_G" || { echo "FATAL: versionName bump failed"; exit 1; }
    echo "  [ok] version -> 1.4.6 (versionCode 13)"
fi

# --- Final feature verification. ----------------------------------------------
verify() {
    if ! grep -qF "$2" "$1"; then
        echo "FATAL: $1 does not contain: $2"
        exit 1
    fi
}
verify "$HOME_KT" 'FilenameTemplateDialog'
verify "$HOME_KT" 'rememberPressScale'
verify "$HOME_KT" 'templateTokens'
verify "$HOME_KT" 'Color(0xFFD32F2F)'
verify "$HOME_KT" 'collectIsPressedAsState'
verify "$HOME_KT" 'IntrinsicSize.Min'
verify "$HOME_KT" 'aspectRatio(1f)'
verify "$HOME_KT" 'onReset = { viewModel.resetScreen() }'
verify "$VM_KT"   'embedMetadata by mutableStateOf(true)'
verify "$SVC_KT"  'Regex("%(?!\\()")'
verify "$BUILD_G" 'versionCode = 13'
verify "$BUILD_G" 'versionName = "1.4.6"'
echo "== FFMux patch 13 applied: v1.4.6 (versionCode 13) =="
