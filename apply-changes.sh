#!/usr/bin/env bash
set -euo pipefail

# =====================================================================
# FFMux patch 22  ->  v1.4.15 (versionCode 22)
#
# 1. The installed version ("v1.4.15") is now shown next to the
#    "Download" title on the Home screen, so it is always visible
#    WHICH build is running on the phone when checking the UI.
# 2. Tapping the circular Download button (or the full-width one)
#    now hides the soft keyboard and clears focus before the
#    clipboard link is pasted and the fetch starts.
# 3. Version bump 1.4.14/21 -> 1.4.15/22.
#
# The pencil button layout is NOT changed by this patch: since
# v1.4.14 it is sized directly from the Author field's real laid-out
# height (onSizeChanged -> .size(authorHeight)), so it is equal to
# the Author row by construction.  A screenshot showing a taller
# button means an older APK is installed -- check the new version
# tag next to the "Download" title after updating.
#
# Safe mode: sha256 baselines are verified before and after, every
# replacement is anchored and counted, and the run is idempotent.
# No file under .github/ is touched.
# =====================================================================

cd "$(dirname "$0")"

echo "== FFMux patch 22 (v1.4.15) =="

HOME="app/src/main/java/com/ffmux/app/ui/home/HomeScreen.kt"
GRADLE="app/build.gradle.kts"

# ---------------------------------------------------------------------
# Already patched (hash-verified)?  Then this is a no-op.
# ---------------------------------------------------------------------
hash_is() {
    [ "$(sha256sum "$1" 2>/dev/null | awk '{print $1}')" = "$2" ]
}

if hash_is "$HOME" 571aac56d73221dbbf0c6c910a97c216979a6b5e8b943fd4006038aaf382458f && hash_is "$GRADLE" 641e36030a891c2efaf3f11966f9d9ca62a1952f0c7429c66ef46e6d273bb50b; then
    echo "Already patched (hashes verified) -- nothing to do."
    exit 0
fi

# ---------------------------------------------------------------------
# Baseline check: the tree must be exactly v1.4.14 (post patch 21).
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
        echo "The repository is not in the expected v1.4.14 state."
        exit 1
    fi
}

verify "$HOME"   e99035456c12f5529b86fb136caca9207dd2fa7e85b4375715449b22d193f21f
verify "$GRADLE" 532126e39a183d9491b5a0dbd046721fb6793f256e8b0f157c9bb2055048bf13

echo "Baselines verified (v1.4.14)."

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
# HomeScreen.kt -- version tag + hide keyboard on fetch tap
# =====================================================================
HOME = "app/src/main/java/com/ffmux/app/ui/home/HomeScreen.kt"

HOME_PAIRS = [
    ("""import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
""",
     """import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.LocalFocusManager
import androidx.compose.ui.graphics.Color
""", 1),
    ("""import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
""",
     """import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.semantics.Role
""", 1),
    ("""    // One circular action: when the field is empty the clipboard link is
    // pasted in first, then the video info is fetched right away.
    val onFetchClicked: () -> Unit = {
        if (viewModel.url.isBlank()) {
""",
     """    // Tapping either fetch button dismisses the soft keyboard first:
    // the link usually arrives from the clipboard, so an open keyboard
    // would only cover the format list that appears right after.
    val keyboard = LocalSoftwareKeyboardController.current
    val focusManager = LocalFocusManager.current

    // One circular action: when the field is empty the clipboard link is
    // pasted in first, then the video info is fetched right away.
    val onFetchClicked: () -> Unit = {
        keyboard?.hide()
        focusManager.clearFocus()
        if (viewModel.url.isBlank()) {
""", 1),
    ("""    Column(modifier = Modifier.fillMaxSize()) {
        ScreenHeader(title = "Download")
""",
     """    // Build tag shown next to the title so it is always visible which
    // version is actually installed on this device.
    val context = LocalContext.current
    val appVersion = remember {
        runCatching {
            context.packageManager.getPackageInfo(context.packageName, 0).versionName
        }.getOrNull() ?: "?"
    }

    Column(modifier = Modifier.fillMaxSize()) {
        ScreenHeader(title = "Download") {
            Text(
                text = "v$appVersion",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
""", 1),
]

patch(HOME, HOME_PAIRS)

# =====================================================================
# app/build.gradle.kts -- 1.4.14/21 -> 1.4.15/22
# =====================================================================
GRADLE = "app/build.gradle.kts"

GRADLE_PAIRS = [
    ("""versionCode = 21""",
     """versionCode = 22""", 1),
    ('versionName = "1.4.14"',
     'versionName = "1.4.15"', 1),
]

patch(GRADLE, GRADLE_PAIRS)

print("patched: HomeScreen.kt, app/build.gradle.kts")
PYEOF

# ---------------------------------------------------------------------
# Post-verification: the tree must now be exactly v1.4.15.
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

verify_post "$HOME"   571aac56d73221dbbf0c6c910a97c216979a6b5e8b943fd4006038aaf382458f
verify_post "$GRADLE" 641e36030a891c2efaf3f11966f9d9ca62a1952f0c7429c66ef46e6d273bb50b

echo "Post-patch hashes verified."
echo ""
echo "Patch 22 applied: v1.4.15 (versionCode 22)"
echo "  - version tag next to the Download title"
echo "  - keyboard hides when the Download button is tapped"
echo "  - pencil/Author row already equal since v1.4.14 (untouched)"
