#!/usr/bin/env bash
###############################################################################
# FFMux patch 14 (v1.4.7) -- one-line compile fix for patch 13.
# Run from the repository root:  bash apply-changes.sh
#
# What went wrong: patch 13 added the press-shrink animation and imported
#   import androidx.compose.ui.draw.graphicsLayer
# but since Compose UI 1.7.0 (this project uses the 2024.12.01 compose BOM,
# i.e. ui 1.7.6) Modifier.graphicsLayer lives in the
# androidx.compose.ui.graphics package instead -- it moved out of
# androidx.compose.ui.draw, while Modifier.clip stayed there. The CI build
# therefore failed with:
#   HomeScreen.kt:77:33 Unresolved reference 'graphicsLayer'.
#
# The fix: import androidx.compose.ui.graphics.graphicsLayer (in the
# alphabetically correct spot, right after ...ui.graphics.Color). Nothing
# else changes -- every patch 13 feature (filename template picker,
# editable Title/Author, metadata ON by default, solid red reset X,
# press-shrink feedback, template-safe download names) is untouched.
#
# Same safety design as patches 10-13:
#   * the exact input state is verified with sha256 before anything is
#     touched, and the exact output state is verified afterwards,
#   * the single replacement is applied only when its anchor matches
#     exactly once,
#   * running the script again on a patched tree is a clean no-op.
#
# App version after this script: 1.4.7 (versionCode 14).
#
# Base verified by this script: the tree produced by patch 13
# (v1.4.6, versionCode 13, commit 6d9f777).
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

# --- sha256 of the expected OUTPUT (patched, v1.4.7) tree ----------------------
OUT_HASHES='3745d30b608c6a8c1dedbe342696f43ebc464c9906f4ba828ab87cd3bbdac85e  app/src/main/java/com/ffmux/app/ui/home/HomeScreen.kt
1abce1334a0b86761921a8ea3db1883f8aa7deceaddf274c422d00a798d93905  app/src/main/java/com/ffmux/app/ui/home/HomeViewModel.kt
2a48c4f1a6a2ccecaa9df891f0c7e09c6230ecd3ce3979fb1dc7ce51bbd06af9  app/src/main/java/com/ffmux/app/engine/DownloadService.kt'

output_matches() {
    printf '%s\n' "$OUT_HASHES" | (cd "$(dirname "$0")" && sha256sum -c --status -) 2>/dev/null
}

# --- sha256 of the expected INPUT (v1.4.6 base) tree ---------------------------
BASE_HASHES='c3775fd7f987c6b3e8b136b269c7554590be451569158a7df60d321bd05ae827  app/src/main/java/com/ffmux/app/ui/home/HomeScreen.kt
1abce1334a0b86761921a8ea3db1883f8aa7deceaddf274c422d00a798d93905  app/src/main/java/com/ffmux/app/ui/home/HomeViewModel.kt
2a48c4f1a6a2ccecaa9df891f0c7e09c6230ecd3ce3979fb1dc7ce51bbd06af9  app/src/main/java/com/ffmux/app/engine/DownloadService.kt'

base_matches() {
    printf '%s\n' "$BASE_HASHES" | (cd "$(dirname "$0")" && sha256sum -c --status -) 2>/dev/null
}

if output_matches; then
    echo "  [skip] sources are already patched (v1.4.7 tree detected)"
else
    if ! base_matches; then
        echo "FATAL: the source files are neither the expected v1.4.6 base"
        echo "       nor the patched v1.4.7 tree. Another patch version seems"
        echo "       to have been applied in between -- do not force this."
        exit 1
    fi
    echo "  [ok] base state verified (exact v1.4.6 tree, sha256)"

    python3 - <<'PYEOF'
import sys

PATCHES = [
    # (path, [(old, new), ...])
    (r'''app/src/main/java/com/ffmux/app/ui/home/HomeScreen.kt''', [
        # graphicsLayer moved to the androidx.compose.ui.graphics package in
        # Compose UI 1.7 -- fix the import, keep the list alphabetical.
        (r'''
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.graphicsLayer
import androidx.compose.ui.graphics.Color
''', r'''
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
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
# the anchor matched exactly once -- write the file
for path, src in results:
    with open(path, "w", encoding="utf-8") as f:
        f.write(src)
    print("  [ok] patched " + path)

PYEOF

    printf '%s\n' "$OUT_HASHES" | sha256sum -c --status || {
        echo "FATAL: patched files do not match the verified v1.4.7 tree"
        exit 1
    }
    echo "  [ok] patched tree verified (exact v1.4.7 tree, sha256)"
fi

# --- Version bump: -> 1.4.7 (versionCode 14). --------------------------------
if grep -qF 'versionName = "1.4.7"' "$BUILD_G" && grep -qF 'versionCode = 14' "$BUILD_G"; then
    echo "  [skip] version is already 1.4.7 (versionCode 14)"
else
    sed -i -E 's/versionCode = [0-9]+/versionCode = 14/' "$BUILD_G"
    sed -i -E 's/versionName = "[^"]+"/versionName = "1.4.7"/' "$BUILD_G"
    grep -qF 'versionCode = 14' "$BUILD_G" || { echo "FATAL: versionCode bump failed"; exit 1; }
    grep -qF 'versionName = "1.4.7"' "$BUILD_G" || { echo "FATAL: versionName bump failed"; exit 1; }
    echo "  [ok] version -> 1.4.7 (versionCode 14)"
fi

# --- Final feature verification. ----------------------------------------------
verify() {
    if ! grep -qF "$2" "$1"; then
        echo "FATAL: $1 does not contain: $2"
        exit 1
    fi
}
verify "$HOME_KT" 'import androidx.compose.ui.graphics.graphicsLayer'
verify "$HOME_KT" 'Modifier.graphicsLayer {'
verify "$HOME_KT" 'rememberPressScale'
verify "$HOME_KT" 'FilenameTemplateDialog'
verify "$HOME_KT" 'templateTokens'
verify "$HOME_KT" 'Color(0xFFD32F2F)'
verify "$HOME_KT" 'collectIsPressedAsState'
verify "$HOME_KT" 'onReset = { viewModel.resetScreen() }'
verify "$VM_KT"   'embedMetadata by mutableStateOf(true)'
verify "$SVC_KT"  'Regex("%(?!\\()")'
verify "$BUILD_G" 'versionCode = 14'
verify "$BUILD_G" 'versionName = "1.4.7"'
if grep -qF 'import androidx.compose.ui.draw.graphicsLayer' "$HOME_KT"; then
    echo "FATAL: the broken pre-1.7 import is still in HomeScreen.kt"
    exit 1
fi
echo "== FFMux patch 14 applied: v1.4.7 (versionCode 14) =="
