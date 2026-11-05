#!/usr/bin/env bash
set -euo pipefail

# =====================================================================
# FFMux patch 24  ->  v1.4.17 (versionCode 24)
#
# REDESIGN of the pencil button, as requested: the standalone button
# next to the Author field could not be made reliably equal in height,
# so it is gone.  The pencil now lives INSIDE the Title field (the
# file-name input) as a standard Material 3 trailing icon:
#   - the text field lays the icon out itself, vertically centered,
#     at the field's own height -> a size mismatch is structurally
#     impossible;
#   - tapping it opens the exact same filename-template dialog as
#     before (same functionality);
#   - the Author input becomes a plain full-width field.
#
# Also kept from earlier patches: the version tag next to the
# "Download" title and the keyboard hiding on the Download button.
# Version bump 1.4.16/23 -> 1.4.17/24.
#
# Safe mode: sha256 baselines are verified before and after, every
# replacement is anchored and counted, and the run is idempotent.
# No file under .github/ is touched.
# =====================================================================

cd "$(dirname "$0")"

echo "== FFMux patch 24 (v1.4.17) =="

HOME="app/src/main/java/com/ffmux/app/ui/home/HomeScreen.kt"
GRADLE="app/build.gradle.kts"

# ---------------------------------------------------------------------
# Already patched (hash-verified)?  Then this is a no-op.
# ---------------------------------------------------------------------
hash_is() {
    [ "$(sha256sum "$1" 2>/dev/null | awk '{print $1}')" = "$2" ]
}

if hash_is "$HOME" 2b3ad5d31a5989347a949dd69ab0c3ec0edac40084db5ace7ba96c9be3f00b17 && hash_is "$GRADLE" 75a3a4cd7714da80b814ac9ca758c9cd729745604ec0f8da75f5e604c81b8080; then
    echo "Already patched (hashes verified) -- nothing to do."
    exit 0
fi

# ---------------------------------------------------------------------
# Baseline check: the tree must be exactly the post-patch-23 state
# (v1.4.16 committed as dc5fbc6).
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
        echo "The repository is not in the expected post-patch-23 state."
        exit 1
    fi
}

verify "$HOME"   1725309e1edc4c81615ec8577b7def1bf33207aeb9aac09f927e10d474a9d310
verify "$GRADLE" 7680abb91412326e8de5b040f67aeb50f304bfba72e71be06be6dc7687414a14

echo "Baselines verified (post patch 23)."

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
# HomeScreen.kt -- pencil into the Title field, Author row simplified
# =====================================================================
HOME = "app/src/main/java/com/ffmux/app/ui/home/HomeScreen.kt"

HOME_PAIRS = [
    ("""import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
""",
     """import androidx.compose.foundation.border
import androidx.compose.foundation.interaction.MutableInteractionSource
""", 1),
    ("""import androidx.compose.material3.RadioButton
import androidx.compose.material3.ripple
import androidx.compose.material3.Surface
""",
     """import androidx.compose.material3.RadioButton
import androidx.compose.material3.Surface
""", 1),
    ("""import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalClipboardManager
""",
     """import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalClipboardManager
""", 1),
    ("""import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontFamily
""",
     """import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.text.font.FontFamily
""", 1),
    ("""                OutlinedTextField(
                    value = title,
                    onValueChange = onTitleChange,
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("Title") },
                    singleLine = true,
                    textStyle = MaterialTheme.typography.titleMedium,
                    shape = MaterialTheme.shapes.small
                )
""",
     """                // The filename-template pencil lives INSIDE the
                // Title field as a standard trailing icon: the text
                // field lays the icon out itself, perfectly centered
                // and at the field's own height, so a size mismatch
                // is structurally impossible. Tapping it opens the
                // same template dialog as before.
                OutlinedTextField(
                    value = title,
                    onValueChange = onTitleChange,
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("Title") },
                    singleLine = true,
                    textStyle = MaterialTheme.typography.titleMedium,
                    shape = MaterialTheme.shapes.small,
                    trailingIcon = {
                        IconButton(onClick = { showTemplate = true }) {
                            Icon(
                                imageVector = Icons.Outlined.Edit,
                                contentDescription = "Filename template",
                                tint = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                )
""", 1),
    ("""                Spacer(Modifier.height(8.dp))
                // The pencil no longer derives its size from layout
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
""",
     """                Spacer(Modifier.height(8.dp))
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
""", 1),
]

patch(HOME, HOME_PAIRS)

# =====================================================================
# app/build.gradle.kts -- 1.4.16/23 -> 1.4.17/24
# =====================================================================
GRADLE = "app/build.gradle.kts"

GRADLE_PAIRS = [
    ("""versionCode = 23""",
     """versionCode = 24""", 1),
    ('versionName = "1.4.16"',
     'versionName = "1.4.17"', 1),
]

patch(GRADLE, GRADLE_PAIRS)

print("patched: HomeScreen.kt, app/build.gradle.kts")
PYEOF

# ---------------------------------------------------------------------
# Post-verification: the tree must now be exactly v1.4.17.
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

verify_post "$HOME"   2b3ad5d31a5989347a949dd69ab0c3ec0edac40084db5ace7ba96c9be3f00b17
verify_post "$GRADLE" 75a3a4cd7714da80b814ac9ca758c9cd729745604ec0f8da75f5e604c81b8080

echo "Post-patch hashes verified."
echo ""
echo "Patch 24 applied: v1.4.17 (versionCode 24)"
echo "  - pencil is now a trailing icon INSIDE the Title (file name) field"
echo "  - opens the same filename-template dialog on tap"
echo "  - standalone button next to Author removed; Author is full width"
