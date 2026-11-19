#!/usr/bin/env bash
set -euo pipefail

# =====================================================================
# FFMux patch 25  ->  v1.4.18 (versionCode 25)
#
# Adds the Ext section at the head of the Author row, as requested:
#   - a read-only "Ext" field whose default value is mp4;
#   - tapping it opens a menu to pick mp4 / mkv / mov;
#   - the choice becomes the final container of merged video+audio
#     downloads: it is sent to yt-dlp as --merge-output-format (the
#     "ext" part of the command), both in the real download and in
#     the command preview.
#   - mp4 keeps yt-dlp's automatic mkv fallback for codecs mp4 cannot
#     hold (unchanged app behaviour); mkv and mov are forced.
#
# Nothing else is added or removed. No file under .github/ is touched.
# Safe mode: sha256 baselines verified before and after, every
# replacement anchored and counted, and the run is idempotent.
# =====================================================================

cd "$(dirname "$0")"

echo "== FFMux patch 25 (v1.4.18) =="

HOME="app/src/main/java/com/ffmux/app/ui/home/HomeScreen.kt"
VM="app/src/main/java/com/ffmux/app/ui/home/HomeViewModel.kt"
ENGINE="app/src/main/java/com/ffmux/app/engine/YtDlpEngine.kt"
GRADLE="app/build.gradle.kts"

# ---------------------------------------------------------------------
# Already patched (hash-verified)?  Then this is a no-op.
# ---------------------------------------------------------------------
hash_is() {
    [ "$(sha256sum "$1" 2>/dev/null | awk '{print $1}')" = "$2" ]
}

if hash_is "$HOME" 2a030d29465a3ab06446eeb1de857fbf0347b32d0310950700a610016bc72765 && hash_is "$VM" 911c621bc20c32cba95a5d43b60e0d09b21db6296a0604990ed0dd3892d03da7 && \
   hash_is "$ENGINE" 7bcd4aaba6cec4bdc6c0cc3f5837f66bd1f2224dd45e562687bd310a61cf5718 && hash_is "$GRADLE" 6b5f70246f87e132bfea424630dd34339f1ddc22d8e0c4378fda6023ed59099a; then
    echo "Already patched (hashes verified) -- nothing to do."
    exit 0
fi

# ---------------------------------------------------------------------
# Baseline check: the tree must be exactly the post-patch-24 state
# (v1.4.17 committed as de10d2f).
# ---------------------------------------------------------------------
verify() {
    local f="$1" want="$2" got
    if [ ! -f "$f" ]; then
        echo "FATAL: $f is missing."
        exit 1
    fi
    got=$(sha256sum "$f" | awk '{print $1}')
    if [ "$got" != "$want" ]; then
        echo "FATAL: unexpected content in $f"
        echo "  expected sha256 $want"
        echo "  found    sha256 $got"
        echo "The repository is not in the expected post-patch-24 (v1.4.17) state."
        exit 1
    fi
}

verify "$HOME"   2b3ad5d31a5989347a949dd69ab0c3ec0edac40084db5ace7ba96c9be3f00b17
verify "$VM"     1abce1334a0b86761921a8ea3db1883f8aa7deceaddf274c422d00a798d93905
verify "$ENGINE" 287fac8cf3b7f9e443fe4819116745df69297b16dae138bacb69a44d966405e0
verify "$GRADLE" 75a3a4cd7714da80b814ac9ca758c9cd729745604ec0f8da75f5e604c81b8080

echo "Baselines verified (post patch 24)."

# ---------------------------------------------------------------------
# Patch
# ---------------------------------------------------------------------
python3 << 'PYEOF'
import sys

def patch(path, pairs):
    with open(path, "r", encoding="utf-8") as fh:
        src = fh.read()
    for old, new, count in pairs:
        found = src.count(old)
        if found != count:
            print("FATAL: anchor mismatch in %s" % path)
            print("  expected %d occurrence(s), found %d for:" % (count, found))
            print("  %r" % old[:90])
            sys.exit(1)
        src = src.replace(old, new)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(src)

# =====================================================================
# HomeViewModel.kt -- mergeExt state, updater, arg building
# =====================================================================
VM = "app/src/main/java/com/ffmux/app/ui/home/HomeViewModel.kt"

VM_PAIRS = [
    ("""    var editableUploader by mutableStateOf("")
        private set
""",
     """    var editableUploader by mutableStateOf("")
        private set

    /**
     * Final container for merged downloads, picked in the Ext dropdown
     * of the info card: "mp4", "mkv" or "mov". Default mp4. Kept across
     * links like the option chips: it is a preference, not per-link
     * state.
     */
    var mergeExt by mutableStateOf("mp4")
        private set
""", 1),
    ("""    fun updateUploader(value: String) {
        editableUploader = value
    }
""",
     """    fun updateUploader(value: String) {
        editableUploader = value
    }

    fun updateMergeExt(value: String) {
        mergeExt = value
    }
""", 1),
    ("""    /**
     * Extra yt-dlp arguments for the option chips only, as one space
     * separated "--flag value" string. Used by the command preview.
     */
    fun baseDownloadArgs(): String {
""",
     """    /**
     * Extra yt-dlp arguments for the option chips and the merge
     * container picked in the Ext dropdown, as one space separated
     * "--flag value" string. Used by the command preview and by
     * buildDownloadArgs().
     */
    fun baseDownloadArgs(): String {
""", 1),
    ("""        if (embedMetadata) args.add("--embed-metadata")
        if (splitChapters) args.add("--split-chapters")
        if (noPart) args.add("--no-part")
        return args.joinToString(" ")
""",
     """        if (embedMetadata) args.add("--embed-metadata")
        if (splitChapters) args.add("--split-chapters")
        if (noPart) args.add("--no-part")
        // The Ext dropdown: sent only when the selection really merges
        // two streams, exactly the condition the engine used before.
        // mp4 keeps yt-dlp's mkv fallback ("mp4/mkv") so codecs mp4
        // cannot hold still merge; mkv and mov are forced as chosen.
        if (selectedSelector()?.contains('+') == true) {
            args.add("--merge-output-format")
            args.add(
                when (mergeExt) {
                    "mkv" -> "mkv"
                    "mov" -> "mov"
                    else -> "mp4/mkv"
                }
            )
        }
        return args.joinToString(" ")
""", 1),
]

patch(VM, VM_PAIRS)

# =====================================================================
# YtDlpEngine.kt -- the merge container now arrives via downloadArgs
# =====================================================================
ENGINE = "app/src/main/java/com/ffmux/app/engine/YtDlpEngine.kt"

ENGINE_PAIRS = [
    ("""     * When the selector merges two streams ("137+140") ffmpeg is asked to
     * remux into mp4 with an mkv fallback, which avoids the
     * "postprocessing: conversion failed" error on mixed codecs.
""",
     """     * When the selector merges two streams ("137+140") ffmpeg is asked
     * to remux into the container picked in the Ext dropdown -- mp4
     * with an mkv fallback, or plain mkv / mov; the flag travels inside
     * [extraArgs] -- which avoids the "postprocessing: conversion
     * failed" error on mixed codecs.
""", 1),
    ("""            addOption("--socket-timeout", 30)
            if (selector.contains('+')) {
                addOption("--merge-output-format", "mp4/mkv")
            }
            applyExtraArgs(extraArgs)
""",
     """            addOption("--socket-timeout", 30)
            // --merge-output-format is no longer hardcoded here: the
            // Ext dropdown puts it into the download args, and
            // applyExtraArgs passes it through below.
            applyExtraArgs(extraArgs)
""", 1),
]

patch(ENGINE, ENGINE_PAIRS)

# =====================================================================
# HomeScreen.kt -- Ext dropdown in the Author row, preview wiring
# =====================================================================
HOME = "app/src/main/java/com/ffmux/app/ui/home/HomeScreen.kt"

HOME_PAIRS = [
    ("""import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ElevatedCard
""",
     """import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
""", 1),
    ("""import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
""",
     """import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.MenuAnchorType
import androidx.compose.material3.OutlinedTextField
""", 1),
    ("""                InfoCard(
                    info = infoState.info,
                    title = viewModel.editableTitle,
                    onTitleChange = { viewModel.updateTitle(it) },
                    uploader = viewModel.editableUploader,
                    onUploaderChange = { viewModel.updateUploader(it) }
                )
""",
     """                InfoCard(
                    info = infoState.info,
                    title = viewModel.editableTitle,
                    onTitleChange = { viewModel.updateTitle(it) },
                    uploader = viewModel.editableUploader,
                    onUploaderChange = { viewModel.updateUploader(it) },
                    mergeExt = viewModel.mergeExt,
                    onMergeExtChange = { viewModel.updateMergeExt(it) }
                )
""", 1),
    ("""private fun InfoCard(
    info: VideoInfo,
    title: String,
    onTitleChange: (String) -> Unit,
    uploader: String,
    onUploaderChange: (String) -> Unit
) {
""",
     """private fun InfoCard(
    info: VideoInfo,
    title: String,
    onTitleChange: (String) -> Unit,
    uploader: String,
    onUploaderChange: (String) -> Unit,
    mergeExt: String,
    onMergeExtChange: (String) -> Unit
) {
""", 1),
    ("""                Spacer(Modifier.height(8.dp))
                // The pencil button that used to sit beside this field
                // is gone -- it moved into the Title (file name) field
                // above as a trailing icon. The Author input is now a
                // plain full-width field with nothing next to it.
                OutlinedTextField(
                    value = uploader,
                    onValueChange = onUploaderChange,
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("Author") },
                    singleLine = true,
                    textStyle = MaterialTheme.typography.bodyMedium,
                    shape = MaterialTheme.shapes.small
                )
""",
     """                Spacer(Modifier.height(8.dp))
                // Ext picker at the head of the Author row, as ordered:
                // the final container of a merged video+audio download,
                // the "ext" part of the yt-dlp command
                // (--merge-output-format). Default mp4; the menu offers
                // mp4 / mkv / mov.
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    ExtDropdown(
                        selected = mergeExt,
                        onSelected = onMergeExtChange
                    )
                    Spacer(Modifier.width(8.dp))
                    OutlinedTextField(
                        value = uploader,
                        onValueChange = onUploaderChange,
                        modifier = Modifier.weight(1f),
                        label = { Text("Author") },
                        singleLine = true,
                        textStyle = MaterialTheme.typography.bodyMedium,
                        shape = MaterialTheme.shapes.small
                    )
                }
""", 1),
    (r"""    parts.add("--socket-timeout")
    parts.add("30")
    if (selector != null && selector.contains('+')) {
        parts.add("--merge-output-format")
        parts.add("mp4/mkv")
    }
    baseArgs.split(Regex("\\s+")).filter { it.isNotBlank() }.forEach { parts.add(it) }
""",
     r"""    parts.add("--socket-timeout")
    parts.add("30")
    // The merge container is no longer added here: the Ext dropdown
    // puts --merge-output-format into baseArgs, and the engine receives
    // it the same way, so the preview keeps mirroring the real command.
    baseArgs.split(Regex("\\s+")).filter { it.isNotBlank() }.forEach { parts.add(it) }
""", 1),
    ("""/** One yt-dlp output template field offered in the picker dialog. */
""",
     """/**
 * Container picker at the head of the Author row: the final extension
 * of a merged video+audio download, passed to yt-dlp as
 * --merge-output-format. Default mp4, menu offers mp4 / mkv / mov.
 * The field is read-only text: tapping it opens the menu.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ExtDropdown(
    selected: String,
    onSelected: (String) -> Unit
) {
    val options = listOf("mp4", "mkv", "mov")
    val expanded = rememberSaveable { mutableStateOf(false) }
    ExposedDropdownMenuBox(
        expanded = expanded.value,
        onExpandedChange = { expanded.value = it }
    ) {
        OutlinedTextField(
            value = selected,
            onValueChange = {},
            modifier = Modifier
                .menuAnchor(MenuAnchorType.PrimaryNotEditable)
                .width(128.dp),
            label = { Text("Ext") },
            singleLine = true,
            readOnly = true,
            textStyle = MaterialTheme.typography.bodyMedium,
            shape = MaterialTheme.shapes.small,
            trailingIcon = {
                ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded.value)
            }
        )
        ExposedDropdownMenu(
            expanded = expanded.value,
            onDismissRequest = { expanded.value = false }
        ) {
            options.forEach { option ->
                DropdownMenuItem(
                    text = { Text(option) },
                    onClick = {
                        onSelected(option)
                        expanded.value = false
                    }
                )
            }
        }
    }
}

/** One yt-dlp output template field offered in the picker dialog. */
""", 1),
]

patch(HOME, HOME_PAIRS)

# =====================================================================
# app/build.gradle.kts -- 1.4.17/24 -> 1.4.18/25
# =====================================================================
GRADLE = "app/build.gradle.kts"

GRADLE_PAIRS = [
    ("""versionCode = 24""",
     """versionCode = 25""", 1),
    ('versionName = "1.4.17"',
     'versionName = "1.4.18"', 1),
]

patch(GRADLE, GRADLE_PAIRS)

print("patched: HomeViewModel.kt, YtDlpEngine.kt, HomeScreen.kt, app/build.gradle.kts")
PYEOF

# ---------------------------------------------------------------------
# Post-verification: the tree must now be exactly v1.4.18.
# ---------------------------------------------------------------------
verify_post() {
    local f="$1" want="$2" got
    got=$(sha256sum "$f" | awk '{print $1}')
    if [ "$got" != "$want" ]; then
        echo "FATAL: post-patch verification failed for $f"
        echo "  expected sha256 $want"
        echo "  found    sha256 $got"
        exit 1
    fi
}

verify_post "$HOME"   2a030d29465a3ab06446eeb1de857fbf0347b32d0310950700a610016bc72765
verify_post "$VM"     911c621bc20c32cba95a5d43b60e0d09b21db6296a0604990ed0dd3892d03da7
verify_post "$ENGINE" 7bcd4aaba6cec4bdc6c0cc3f5837f66bd1f2224dd45e562687bd310a61cf5718
verify_post "$GRADLE" 6b5f70246f87e132bfea424630dd34339f1ddc22d8e0c4378fda6023ed59099a

echo "Post-patch hashes verified."
echo ""
echo "Patch 25 applied: v1.4.18 (versionCode 25)"
echo "  - Ext section added at the head of the Author row (default mp4)"
echo "  - tapping it opens a menu: mp4 / mkv / mov"
echo "  - choice is sent to yt-dlp as --merge-output-format when merging"
echo "  - command preview shows the same flag"
echo "  - nothing else added or removed"
