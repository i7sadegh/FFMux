#!/usr/bin/env bash
###############################################################################
# FFMux patch 15 (v1.4.8) -- two UI polish fixes from user feedback.
# Run from the repository root:  bash apply-changes.sh
#
# 1. Pencil button next to the Author field was taller than the field and
#    stuck out above it (measured on a real screenshot: 163px button vs a
#    142px field -- the IntrinsicSize.Min + fillMaxHeight + aspectRatio
#    cocktail sizes the button past the field). The Author field is now
#    measured live with onSizeChanged and the pencil is given exactly that
#    size, so it is always a perfect 1:1 square flush with the field on
#    every density and font scale -- no intrinsic-size guessing at all.
#
# 2. Recording duration dialog wasted vertical space: every option row was
#    as tall as the RadioButton's invisible 48dp minimum touch padding
#    (~56dp per line for 24dp of text). The radio is now capped at 24dp
#    and the row padding halved, so the preset list is roughly half as
#    tall. Tapping anywhere on a row still picks it (the whole row was and
#    stays the tap target), so nothing is lost.
#
# Same safety design as patches 10-14:
#   * the exact input state is verified with sha256 before anything is
#     touched, and the exact output state is verified afterwards,
#   * every replacement is applied only when its anchor matches exactly
#     once, and files are written only after all hunks matched,
#   * running the script again on a patched tree is a clean no-op.
#
# App version after this script: 1.4.8 (versionCode 15).
#
# Base verified by this script: the tree produced by patch 14
# (v1.4.7, versionCode 14, commit fee79ac).
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

# --- sha256 of the expected OUTPUT (patched, v1.4.8) tree ----------------------
OUT_HASHES='dfc8d0f18451fb9cb02e957d56c8e7b912dcc6ff911b2e8908f8335da22f8b9f  app/src/main/java/com/ffmux/app/ui/home/HomeScreen.kt
1abce1334a0b86761921a8ea3db1883f8aa7deceaddf274c422d00a798d93905  app/src/main/java/com/ffmux/app/ui/home/HomeViewModel.kt
2a48c4f1a6a2ccecaa9df891f0c7e09c6230ecd3ce3979fb1dc7ce51bbd06af9  app/src/main/java/com/ffmux/app/engine/DownloadService.kt'

output_matches() {
    printf '%s\n' "$OUT_HASHES" | (cd "$(dirname "$0")" && sha256sum -c --status -) 2>/dev/null
}

# --- sha256 of the expected INPUT (v1.4.7 base) tree ---------------------------
BASE_HASHES='3745d30b608c6a8c1dedbe342696f43ebc464c9906f4ba828ab87cd3bbdac85e  app/src/main/java/com/ffmux/app/ui/home/HomeScreen.kt
1abce1334a0b86761921a8ea3db1883f8aa7deceaddf274c422d00a798d93905  app/src/main/java/com/ffmux/app/ui/home/HomeViewModel.kt
2a48c4f1a6a2ccecaa9df891f0c7e09c6230ecd3ce3979fb1dc7ce51bbd06af9  app/src/main/java/com/ffmux/app/engine/DownloadService.kt'

base_matches() {
    printf '%s\n' "$BASE_HASHES" | (cd "$(dirname "$0")" && sha256sum -c --status -) 2>/dev/null
}

if output_matches; then
    echo "  [skip] sources are already patched (v1.4.8 tree detected)"
else
    if ! base_matches; then
        echo "FATAL: the source files are neither the expected v1.4.7 base"
        echo "       nor the patched v1.4.8 tree. Another patch version seems"
        echo "       to have been applied in between -- do not force this."
        exit 1
    fi
    echo "  [ok] base state verified (exact v1.4.7 tree, sha256)"

    python3 - <<'PYEOF'
import sys

PATCHES = [
    # (path, [(old, new), ...])
    (r'''app/src/main/java/com/ffmux/app/ui/home/HomeScreen.kt''', [

        # --- imports for the live-measured pencil size -----------------------
        (r'''
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalConfiguration
''', r'''
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
'''),

        # --- pencil button: exactly the Author field height, 1:1 -------------
        (r'''
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
''', r'''
                Spacer(Modifier.height(8.dp))
                // The pencil is sized to the exact height the Author field
                // renders at, measured live after layout: the two are always
                // flush on every density and font scale, and the button is a
                // perfect 1:1 square -- it no longer sticks out above the row.
                val density = LocalDensity.current
                var authorHeightPx by remember { mutableStateOf<Int?>(null) }
                val pencilSize = authorHeightPx?.let { with(density) { it.toDp() } } ?: 56.dp
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    OutlinedTextField(
                        value = uploader,
                        onValueChange = onUploaderChange,
                        modifier = Modifier
                            .weight(1f)
                            .onSizeChanged { authorHeightPx = it.height },
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
                            .size(pencilSize),
                        shape = MaterialTheme.shapes.small
                    ) {
                        Icon(
                            imageVector = Icons.Outlined.Edit,
                            contentDescription = "Filename template"
                        )
                    }
                }
'''),

        # --- duration dialog: compact preset rows ----------------------------
        (r'''
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
''', r'''
                durationPresets.forEach { preset ->
                    // Compact rows: the radio is capped at 24dp so its 48dp
                    // touch padding no longer doubles the height of every
                    // line -- the whole row stays the tap target.
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(MaterialTheme.shapes.extraSmall)
                            .selectable(selected = picked == preset, onClick = { picked = preset })
                            .padding(vertical = 2.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        RadioButton(
                            selected = picked == preset,
                            onClick = { picked = preset },
                            modifier = Modifier.size(24.dp)
                        )
                        Spacer(Modifier.width(10.dp))
                        Text(
                            text = if (preset == 0) "No limit" else durationText(preset),
                            style = MaterialTheme.typography.bodyLarge
                        )
                    }
                }
'''),

        # --- duration dialog: compact custom minutes row ---------------------
        (r'''
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
''', r'''
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(MaterialTheme.shapes.extraSmall)
                        .selectable(selected = picked == -1, onClick = { picked = -1 })
                        .padding(vertical = 2.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    RadioButton(
                        selected = picked == -1,
                        onClick = { picked = -1 },
                        modifier = Modifier.size(24.dp)
                    )
                    Spacer(Modifier.width(10.dp))
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
# every anchor matched exactly once -- write the file
for path, src in results:
    with open(path, "w", encoding="utf-8") as f:
        f.write(src)
    print("  [ok] patched " + path)

PYEOF

    printf '%s\n' "$OUT_HASHES" | sha256sum -c --status || {
        echo "FATAL: patched files do not match the verified v1.4.8 tree"
        exit 1
    }
    echo "  [ok] patched tree verified (exact v1.4.8 tree, sha256)"
fi

# --- Version bump: -> 1.4.8 (versionCode 15). --------------------------------
if grep -qF 'versionName = "1.4.8"' "$BUILD_G" && grep -qF 'versionCode = 15' "$BUILD_G"; then
    echo "  [skip] version is already 1.4.8 (versionCode 15)"
else
    sed -i -E 's/versionCode = [0-9]+/versionCode = 15/' "$BUILD_G"
    sed -i -E 's/versionName = "[^"]+"/versionName = "1.4.8"/' "$BUILD_G"
    grep -qF 'versionCode = 15' "$BUILD_G" || { echo "FATAL: versionCode bump failed"; exit 1; }
    grep -qF 'versionName = "1.4.8"' "$BUILD_G" || { echo "FATAL: versionName bump failed"; exit 1; }
    echo "  [ok] version -> 1.4.8 (versionCode 15)"
fi

# --- Final feature verification. ----------------------------------------------
verify() {
    if ! grep -qF "$2" "$1"; then
        echo "FATAL: $1 does not contain: $2"
        exit 1
    fi
}
verify "$HOME_KT" 'import androidx.compose.ui.layout.onSizeChanged'
verify "$HOME_KT" 'import androidx.compose.ui.platform.LocalDensity'
verify "$HOME_KT" '.onSizeChanged { authorHeightPx = it.height }'
verify "$HOME_KT" '.size(pencilSize)'
verify "$HOME_KT" 'modifier = Modifier.size(24.dp)'
verify "$HOME_KT" 'Modifier.graphicsLayer {'
verify "$HOME_KT" 'import androidx.compose.ui.graphics.graphicsLayer'
verify "$HOME_KT" 'FilenameTemplateDialog'
verify "$HOME_KT" 'rememberPressScale'
verify "$HOME_KT" 'templateTokens'
verify "$HOME_KT" 'Color(0xFFD32F2F)'
verify "$HOME_KT" 'collectIsPressedAsState'
verify "$HOME_KT" 'onReset = { viewModel.resetScreen() }'
verify "$VM_KT"   'embedMetadata by mutableStateOf(true)'
verify "$SVC_KT"  'Regex("%(?!\\()")'
verify "$BUILD_G" 'versionCode = 15'
verify "$BUILD_G" 'versionName = "1.4.8"'
if grep -qF 'IntrinsicSize.Min' "$HOME_KT"; then
    echo "FATAL: the intrinsic-size row is still in HomeScreen.kt"
    exit 1
fi
if grep -qF 'aspectRatio(1f)' "$HOME_KT"; then
    echo "FATAL: the old pencil aspectRatio is still in HomeScreen.kt"
    exit 1
fi
if grep -qF 'import androidx.compose.ui.draw.graphicsLayer' "$HOME_KT"; then
    echo "FATAL: the broken pre-1.7 import is still in HomeScreen.kt"
    exit 1
fi
echo "== FFMux patch 15 applied: v1.4.8 (versionCode 15) =="
