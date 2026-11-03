#!/usr/bin/env bash
###############################################################################
# FFMux patch 9 (v1.4.2) -- targeted, idempotent, fail-loud.
# Run from the repository root:  bash apply-changes.sh
#
# Applies on top of the patch-8 tree (FFMux 1.4.1, versionCode 8):
#
#   1. Screen-relative sizes instead of fixed dp values:
#        - the big circular fetch button: diameter = exactly HALF THE
#          SCREEN WIDTH; the icon inside (44% of the diameter), the
#          spinner (40%) and the stroke width all scale with it;
#        - the "Get quality" button height = 13% of the screen width,
#          clamped to 46..60dp (still 52dp on a typical 400dp phone);
#        - the sticky Download bar height = 14% of the screen width,
#          clamped to 48..64dp (still 56dp on a typical 400dp phone).
#   2. Even vertical rhythm on the Home screen: the gap between the
#      link field, the "Get quality" button and the thumbnail card is
#      now the same 12dp on both sides (patch 8 left 0dp between the
#      button and the card).
#   3. Estimated sizes use the real "approximately equal" sign now:
#      the words "approx." and "~" in the download bar, the Best card
#      and the format cards are replaced by the Kotlin escape \u2248.
#
# Safe to run twice: every change is applied only if its old pattern
# is found exactly as expected, skipped if the new pattern is already
# there, and any unexpected state aborts with FATAL -- the script can
# never silently produce a broken tree.
#
# App version after this script: 1.4.2 (versionCode 9).
###############################################################################
set -euo pipefail
if LC_ALL=C grep -qn '[^ -~]' "$0"; then
    echo "FATAL: non-ascii byte in this script"
    exit 1
fi

HOME_KT="app/src/main/java/com/ffmux/app/ui/home/HomeScreen.kt"
BUILD_G="app/build.gradle.kts"
for f in "$HOME_KT" "$BUILD_G"; do
    if [ ! -f "$f" ]; then
        echo "FATAL: $f not found - run from the repository root"
        exit 1
    fi
done

echo "== FFMux patch 9: screen-relative sizes, even 12dp rhythm, approx sign =="

# --- 1a. Circular button diameter: 96dp -> exactly 50% of screen width. ----
if [ "$(grep -cF 'Modifier.size(96.dp)' "$HOME_KT" || true)" -eq 1 ]; then
    sed -i 's/Modifier\.size(96\.dp)/Modifier.size((LocalConfiguration.current.screenWidthDp * 0.5f).dp)/' "$HOME_KT"
    echo "  [ok] circular button diameter -> half the screen width"
elif grep -qF 'screenWidthDp * 0.5f' "$HOME_KT"; then
    echo "  [skip] circular button already uses the screen width"
else
    echo "FATAL: expected exactly one Modifier.size(96.dp) in HomeScreen.kt"
    exit 1
fi

# --- 1b. Icon inside the circle: 42dp -> 44% of the diameter. --------------
if [ "$(grep -cF 'Modifier.size(42.dp)' "$HOME_KT" || true)" -eq 1 ]; then
    sed -i 's/Modifier\.size(42\.dp)/Modifier.size((LocalConfiguration.current.screenWidthDp * 0.22f).dp)/' "$HOME_KT"
    echo "  [ok] circle icon -> 44% of the diameter"
elif grep -qF 'screenWidthDp * 0.22f' "$HOME_KT"; then
    echo "  [skip] circle icon already uses the screen width"
else
    echo "FATAL: expected exactly one Modifier.size(42.dp) in HomeScreen.kt"
    exit 1
fi

# --- 1c. Spinner inside the circle: 38dp -> 40% of the diameter. -----------
if [ "$(grep -cF 'Modifier.size(38.dp)' "$HOME_KT" || true)" -eq 1 ]; then
    sed -i 's/Modifier\.size(38\.dp)/Modifier.size((LocalConfiguration.current.screenWidthDp * 0.20f).dp)/' "$HOME_KT"
    echo "  [ok] circle spinner -> 40% of the diameter"
elif grep -qF 'screenWidthDp * 0.20f' "$HOME_KT"; then
    echo "  [skip] circle spinner already uses the screen width"
else
    echo "FATAL: expected exactly one Modifier.size(38.dp) in HomeScreen.kt"
    exit 1
fi

# --- 1d. Spinner stroke: 3dp -> about 3% of the diameter. ------------------
if [ "$(grep -cF 'strokeWidth = 3.dp' "$HOME_KT" || true)" -eq 1 ]; then
    sed -i 's/strokeWidth = 3\.dp/strokeWidth = (LocalConfiguration.current.screenWidthDp * 0.015f).dp/' "$HOME_KT"
    echo "  [ok] circle spinner stroke scales with the diameter"
elif grep -qF 'screenWidthDp * 0.015f' "$HOME_KT"; then
    echo "  [skip] circle spinner stroke already scales"
else
    echo "FATAL: expected exactly one 'strokeWidth = 3.dp' in HomeScreen.kt"
    exit 1
fi

# --- 1e. "Get quality" height: 52dp -> 13% of width (clamped 46..60dp). ---
if [ "$(grep -cF '.height(52.dp)' "$HOME_KT" || true)" -eq 1 ]; then
    sed -i 's/\.height(52\.dp)/.height((LocalConfiguration.current.screenWidthDp * 0.13f).coerceIn(46f, 60f).dp)/' "$HOME_KT"
    echo "  [ok] Get quality button height -> 13% of the screen width"
elif grep -qF 'screenWidthDp * 0.13f' "$HOME_KT"; then
    echo "  [skip] Get quality button already uses the screen width"
else
    echo "FATAL: expected exactly one .height(52.dp) in HomeScreen.kt"
    exit 1
fi

# --- 1f. Download bar height: 56dp -> 14% of width (clamped 48..64dp). ----
if [ "$(grep -cF '.height(56.dp)' "$HOME_KT" || true)" -eq 1 ]; then
    sed -i 's/\.height(56\.dp)/.height((LocalConfiguration.current.screenWidthDp * 0.14f).coerceIn(48f, 64f).dp)/' "$HOME_KT"
    echo "  [ok] Download bar height -> 14% of the screen width"
elif grep -qF 'screenWidthDp * 0.14f' "$HOME_KT"; then
    echo "  [skip] Download bar already uses the screen width"
else
    echo "FATAL: expected exactly one .height(56.dp) in HomeScreen.kt"
    exit 1
fi

# --- 2. Even 12dp rhythm: link field -> Get quality -> thumbnail. ----------
ANCHOR='HorizontalFetchButton(loading = loading, onClick = onFetchClicked)'
next_line="$(grep -A1 -F "$ANCHOR" "$HOME_KT" | tail -n 1 || true)"
if printf '%s' "$next_line" | grep -qF 'Spacer(Modifier.height(12.dp))'; then
    echo "  [skip] even spacing already in place"
elif [ "$(grep -cF "$ANCHOR" "$HOME_KT" || true)" -eq 1 ]; then
    before="$(grep -cF 'Spacer(Modifier.height(12.dp))' "$HOME_KT" || true)"
    awk -v ins='                Spacer(Modifier.height(12.dp))' -v anchor="$ANCHOR" '
        { print }
        index($0, anchor) { print ins }
    ' "$HOME_KT" > "$HOME_KT.new"
    mv "$HOME_KT.new" "$HOME_KT"
    after="$(grep -cF 'Spacer(Modifier.height(12.dp))' "$HOME_KT" || true)"
    if [ "$after" -ne $((before + 1)) ]; then
        echo "FATAL: spacer insertion failed"
        exit 1
    fi
    echo "  [ok] equal 12dp gaps: field -> button -> thumbnail"
else
    echo "FATAL: expected exactly one HorizontalFetchButton call in HomeScreen.kt"
    exit 1
fi

# --- 3a. Download bar: "approx. 45 MB" -> the approximately-equal sign. ----
if [ "$(grep -cF '"approx. ' "$HOME_KT" || true)" -eq 1 ]; then
    sed -i 's/"approx\. /"\\u2248 /' "$HOME_KT"
    echo "  [ok] download bar uses the approximately-equal sign"
elif grep -qF '\u2248 ${byteSizeText' "$HOME_KT"; then
    echo "  [skip] download bar approx sign already in place"
else
    echo "FATAL: expected the \"approx. \" size string in HomeScreen.kt"
    exit 1
fi

# --- 3b. Cards: "~45MB" -> the sign (best card + format cards). ------------
if [ "$(grep -cF '"~$it"' "$HOME_KT" || true)" -eq 2 ]; then
    sed -i 's/"~\$it"/"\\u2248 $it"/g' "$HOME_KT"
    echo "  [ok] format cards use the approximately-equal sign"
elif grep -qF '\u2248 $it' "$HOME_KT"; then
    echo "  [skip] card approx signs already in place"
else
    echo "FATAL: expected two \"~\$it\" size strings in HomeScreen.kt"
    exit 1
fi

# --- 4. Version bump: 1.4.1 (8) -> 1.4.2 (9). ------------------------------
if grep -qF 'versionName = "1.4.2"' "$BUILD_G" && grep -qF 'versionCode = 9' "$BUILD_G"; then
    echo "  [skip] version is already 1.4.2 (versionCode 9)"
else
    sed -i -E 's/versionCode = [0-9]+/versionCode = 9/' "$BUILD_G"
    sed -i -E 's/versionName = "[^"]+"/versionName = "1.4.2"/' "$BUILD_G"
    grep -qF 'versionCode = 9' "$BUILD_G" || { echo "FATAL: versionCode bump failed"; exit 1; }
    grep -qF 'versionName = "1.4.2"' "$BUILD_G" || { echo "FATAL: versionName bump failed"; exit 1; }
    echo "  [ok] version -> 1.4.2 (versionCode 9)"
fi

# --- 5. Final verification. -------------------------------------------------
grep -qF 'screenWidthDp * 0.5f'  "$HOME_KT" || { echo "FATAL: circle diameter patch missing";    exit 1; }
grep -qF 'screenWidthDp * 0.22f' "$HOME_KT" || { echo "FATAL: circle icon patch missing";        exit 1; }
grep -qF 'screenWidthDp * 0.20f' "$HOME_KT" || { echo "FATAL: circle spinner patch missing";     exit 1; }
grep -qF 'screenWidthDp * 0.13f' "$HOME_KT" || { echo "FATAL: Get quality height patch missing"; exit 1; }
grep -qF 'screenWidthDp * 0.14f' "$HOME_KT" || { echo "FATAL: Download bar height patch missing"; exit 1; }
grep -qF '\u2248 ${byteSizeText' "$HOME_KT" || { echo "FATAL: download bar approx sign missing"; exit 1; }
grep -qF '\u2248 $it' "$HOME_KT" || { echo "FATAL: card approx sign missing"; exit 1; }
if grep -qF '"~$' "$HOME_KT"; then
    echo "FATAL: a tilde size string survived in HomeScreen.kt"
    exit 1
fi
if grep -qF 'approx. ' "$HOME_KT"; then
    echo "FATAL: the word 'approx. ' survived in HomeScreen.kt"
    exit 1
fi
echo "== FFMux patch 9 applied: v1.4.2 (versionCode 9) =="
