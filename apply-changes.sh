#!/usr/bin/env bash
set -euo pipefail

# =====================================================================
# FFMux patch 21  ->  v1.4.14 (versionCode 21)
#
# 1. The pencil button next to the Author field is re-added from
#    scratch and sized by MEASUREMENT instead of layout intrinsics:
#    the Author field reports its real laid-out height through
#    onSizeChanged and the pencil is drawn at exactly that size, so
#    the button outline and the field outline are pixel-flush on
#    every density and font scale (the previous IntrinsicSize +
#    aspectRatio combination reported an inflated height and made
#    the button about 16% taller than the field).
# 2. Version bump 1.4.13/20 -> 1.4.14/21.
#
# Expected starting state: v1.4.13 (versionCode 20).
#
# Safe mode: sha256 baselines verified before and after, every
# replacement anchored and counted, idempotent, no .github/ edits.
# =====================================================================

cd "$(dirname "$0")"

echo "== FFMux patch 21 (v1.4.14) =="

HOME_KT="app/src/main/java/com/ffmux/app/ui/home/HomeScreen.kt"
GRADLE="app/build.gradle.kts"

# ---------------------------------------------------------------------
# Already patched?  Then this is a no-op.
# ---------------------------------------------------------------------
if grep -q 'versionName = "1.4.14"' "$GRADLE" 2>/dev/null && \
   grep -q 'onSizeChanged' "$HOME_KT" 2>/dev/null; then
    echo "Already patched -- nothing to do."
    exit 0
fi

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
        exit 1
    fi
}

# ---------------------------------------------------------------------
# Baselines: both files must be exactly the reviewed v1.4.13 state.
# ---------------------------------------------------------------------
verify "$HOME_KT" cb2391e083a824e0ae93002967f9ece364c3fde2cacf8527968cddc692bff79f

if ! grep -q 'versionCode = 20' "$GRADLE" || \
   ! grep -q 'versionName = "1.4.13"' "$GRADLE"; then
    echo "FATAL: $GRADLE is not v1.4.13 (versionCode 20)."
    exit 1
fi

echo "Baselines verified."

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

HOME_KT = "app/src/main/java/com/ffmux/app/ui/home/HomeScreen.kt"
GRADLE = "app/build.gradle.kts"

# =====================================================================
# HomeScreen.kt -- pencil re-added, sized by the Author field itself
# =====================================================================
home_pairs = [
    ("""import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
""",
     """import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
""", 1),
    ("""import androidx.compose.ui.layout.ContentScale
""",
     """import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onSizeChanged
""", 1),
    ("""import androidx.compose.ui.platform.LocalConfiguration
""",
     """import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
""", 1),
    ("""                // The pencil is rebuilt from scratch: the row takes its
                // height from the Author field itself (IntrinsicSize.Min)
                // and the button simply fills that height, so the two
                // outlines are flush BY CONSTRUCTION -- there is no second
                // hard-coded size that could ever drift apart again, on any
                // density or font scale, and aspectRatio keeps the button
                // a perfect 1:1 square.
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(IntrinsicSize.Min),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    OutlinedTextField(
                        value = uploader,
                        onValueChange = onUploaderChange,
                        modifier = Modifier.weight(1f),
                        label = { Text("Author") },
                        singleLine = true,
                        textStyle = MaterialTheme.typography.bodyMedium,
                        shape = MaterialTheme.shapes.small
                    )
                    Spacer(Modifier.width(8.dp))
                    val pencilInteraction = remember { MutableInteractionSource() }
                    Box(
                        modifier = rememberPressScale(pencilInteraction)
                            .fillMaxHeight()
                            .aspectRatio(1f)
                            .clip(MaterialTheme.shapes.small)
                            .background(MaterialTheme.colorScheme.secondaryContainer)
                            .clickable(
                                interactionSource = pencilInteraction,
                                indication = ripple(),
                                role = Role.Button,
                                onClick = { showTemplate = true }
                            ),
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(
                            imageVector = Icons.Outlined.Edit,
                            contentDescription = "Filename template",
                            tint = MaterialTheme.colorScheme.onSecondaryContainer
                        )
                    }
                }
""",
     """                // The pencil no longer derives its size from layout
                // intrinsics: fillMaxHeight + aspectRatio inside an
                // intrinsically measured row reported an inflated height,
                // so the button came out visibly TALLER than the Author
                // field. Instead the Author field is now measured
                // directly: onSizeChanged publishes its real laid-out
                // height and the pencil is sized to exactly that value,
                // which makes the two outlines pixel-flush BY DATA on
                // every density and font scale and keeps the button a
                // perfect 1:1 square.
                val density = LocalDensity.current
                var authorHeight by remember { mutableStateOf(56.dp) }
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    OutlinedTextField(
                        value = uploader,
                        onValueChange = onUploaderChange,
                        modifier = Modifier
                            .weight(1f)
                            .onSizeChanged { size ->
                                authorHeight = with(density) { size.height.toDp() }
                            },
                        label = { Text("Author") },
                        singleLine = true,
                        textStyle = MaterialTheme.typography.bodyMedium,
                        shape = MaterialTheme.shapes.small
                    )
                    Spacer(Modifier.width(8.dp))
                    val pencilInteraction = remember { MutableInteractionSource() }
                    Box(
                        modifier = rememberPressScale(pencilInteraction)
                            .size(authorHeight)
                            .clip(MaterialTheme.shapes.small)
                            .background(MaterialTheme.colorScheme.secondaryContainer)
                            .clickable(
                                interactionSource = pencilInteraction,
                                indication = ripple(),
                                role = Role.Button,
                                onClick = { showTemplate = true }
                            ),
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(
                            imageVector = Icons.Outlined.Edit,
                            contentDescription = "Filename template",
                            tint = MaterialTheme.colorScheme.onSecondaryContainer
                        )
                    }
                }
""", 1),
]

patch(HOME_KT, home_pairs)

# =====================================================================
# app/build.gradle.kts -- version bump 1.4.13/20 -> 1.4.14/21
# =====================================================================
with open(GRADLE, "r", encoding="utf-8") as fh:
    g = fh.read()

if 'versionCode = 20' in g and 'versionName = "1.4.13"' in g:
    g = g.replace("versionCode = 20", "versionCode = 21", 1)
    g = g.replace('versionName = "1.4.13"', 'versionName = "1.4.14"', 1)
else:
    print("FATAL: gradle version lines not recognised")
    sys.exit(1)

with open(GRADLE, "w", encoding="utf-8") as fh:
    fh.write(g)

print("All patches applied.")
PYEOF

echo "Patches applied."

# ---------------------------------------------------------------------
# Output verification.
# ---------------------------------------------------------------------
verify "$HOME_KT"  e99035456c12f5529b86fb136caca9207dd2fa7e85b4375715449b22d193f21f
verify "$GRADLE"   532126e39a183d9491b5a0dbd046721fb6793f256e8b0f157c9bb2055048bf13

grep -q '.size(authorHeight)' "$HOME_KT" || { echo "FATAL: pencil size binding missing"; exit 1; }
grep -q 'onSizeChanged' "$HOME_KT" || { echo "FATAL: measurement hook missing"; exit 1; }
if grep -q 'IntrinsicSize' "$HOME_KT"; then
    echo "FATAL: IntrinsicSize still present"
    exit 1
fi
grep -q 'versionCode = 21' "$GRADLE" || { echo "FATAL: versionCode not bumped"; exit 1; }

echo "Patch 21 applied cleanly (v1.4.14, versionCode 21)."
exit 0
