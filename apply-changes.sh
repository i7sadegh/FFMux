#!/usr/bin/env bash
set -euo pipefail

# =====================================================================
# FFMux patch 23  ->  v1.4.16 (versionCode 23)
#
# COMPILE FIX for patch 22: the LocalFocusManager import pointed at
# the wrong package (androidx.compose.ui.focus), so Gradle failed
# with "Unresolved reference 'LocalFocusManager'" and no v1.4.15
# APK was produced.  This patch moves that one import to its real
# home (androidx.compose.ui.platform) -- with it in place the module
# compiles (those two lines were the only errors in the CI log) --
# and bumps the version to 1.4.16/23.
#
# Everything else from patch 22 is kept exactly as committed:
#   - version tag ("v1.4.16") next to the Download title
#   - keyboard hides when the Download button is tapped
#   - pencil button equal to the Author row (since v1.4.14)
#
# Safe mode: sha256 baselines are verified before and after, every
# replacement is anchored and counted, and the run is idempotent.
# No file under .github/ is touched.
# =====================================================================

cd "$(dirname "$0")"

echo "== FFMux patch 23 (v1.4.16) =="

HOME="app/src/main/java/com/ffmux/app/ui/home/HomeScreen.kt"
GRADLE="app/build.gradle.kts"

# ---------------------------------------------------------------------
# Already patched (hash-verified)?  Then this is a no-op.
# ---------------------------------------------------------------------
hash_is() {
    [ "$(sha256sum "$1" 2>/dev/null | awk '{print $1}')" = "$2" ]
}

if hash_is "$HOME" 1725309e1edc4c81615ec8577b7def1bf33207aeb9aac09f927e10d474a9d310 && hash_is "$GRADLE" 7680abb91412326e8de5b040f67aeb50f304bfba72e71be06be6dc7687414a14; then
    echo "Already patched (hashes verified) -- nothing to do."
    exit 0
fi

# ---------------------------------------------------------------------
# Baseline check: the tree must be exactly the post-patch-22 state
# (v1.4.15 committed as c5add13).
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
        echo "The repository is not in the expected post-patch-22 state."
        exit 1
    fi
}

verify "$HOME"   571aac56d73221dbbf0c6c910a97c216979a6b5e8b943fd4006038aaf382458f
verify "$GRADLE" 641e36030a891c2efaf3f11966f9d9ca62a1952f0c7429c66ef46e6d273bb50b

echo "Baselines verified (post patch 22)."

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
# HomeScreen.kt -- fix the LocalFocusManager import package
# =====================================================================
HOME = "app/src/main/java/com/ffmux/app/ui/home/HomeScreen.kt"

HOME_PAIRS = [
    ("""import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.LocalFocusManager
import androidx.compose.ui.graphics.Color
""",
     """import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
""", 1),
    ("""import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
""",
     """import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
""", 1),
]

patch(HOME, HOME_PAIRS)

# =====================================================================
# app/build.gradle.kts -- 1.4.15/22 -> 1.4.16/23
# =====================================================================
GRADLE = "app/build.gradle.kts"

GRADLE_PAIRS = [
    ("""versionCode = 22""",
     """versionCode = 23""", 1),
    ('versionName = "1.4.15"',
     'versionName = "1.4.16"', 1),
]

patch(GRADLE, GRADLE_PAIRS)

print("patched: HomeScreen.kt, app/build.gradle.kts")
PYEOF

# ---------------------------------------------------------------------
# Post-verification: the tree must now be exactly v1.4.16.
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

verify_post "$HOME"   1725309e1edc4c81615ec8577b7def1bf33207aeb9aac09f927e10d474a9d310
verify_post "$GRADLE" 7680abb91412326e8de5b040f67aeb50f304bfba72e71be06be6dc7687414a14

echo "Post-patch hashes verified."
echo ""
echo "Patch 23 applied: v1.4.16 (versionCode 23)"
echo "  - LocalFocusManager import fixed (compile error gone)"
echo "  - version tag + keyboard-hide from patch 22 now build"
