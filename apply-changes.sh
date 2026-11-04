#!/usr/bin/env bash
set -euo pipefail

# =====================================================================
# FFMux patch 20  ->  v1.4.13 (versionCode 20)
#
# 1. The pencil button next to the Author field is REBUILT from
#    scratch: the row now takes its height from the Author field
#    itself (IntrinsicSize.Min) and the pencil fills that height,
#    so the two outlines are flush BY CONSTRUCTION -- no hard-coded
#    size that could drift apart -- and the button stays 1:1 square.
# 2. The "Saved as" preview in the filename template dialog no
#    longer cuts the name short with "...": it wraps to as many
#    lines as needed and the middle of the dialog scrolls, so the
#    whole name is always readable with any number of fields on.
# 3. Version bump 1.4.12/19 -> 1.4.13/20.
#
# Expected starting state: v1.4.12 (a stale v1.4.10 tree is also
# accepted -- the version lines are bumped either way).
#
# Safe mode: sha256 baselines verified before and after, every
# replacement anchored and counted, idempotent, no .github/ edits.
# =====================================================================

cd "$(dirname "$0")"

echo "== FFMux patch 20 (v1.4.13) =="

HOME_KT="app/src/main/java/com/ffmux/app/ui/home/HomeScreen.kt"
GRADLE="app/build.gradle.kts"
SETTINGS="app/src/main/java/com/ffmux/app/ui/settings/SettingsScreen.kt"

# ---------------------------------------------------------------------
# Already patched?  Then this is a no-op.
# ---------------------------------------------------------------------
if grep -q 'versionName = "1.4.13"' "$GRADLE" 2>/dev/null && \
   grep -q 'IntrinsicSize.Min' "$HOME_KT" 2>/dev/null; then
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
# Baselines: HomeScreen must be exactly the reviewed pre-patch file.
# The gradle file may be v1.4.12 (normal) or v1.4.10 (stale checkout).
# ---------------------------------------------------------------------
verify "$HOME_KT" a8a58406f40cbe3ee85a7d615fb5df0d50b45f48e7fe6d25f48f6da072c7baa5

if ! grep -q 'versionCode = 19' "$GRADLE" || \
   ! grep -q 'versionName = "1.4.12"' "$GRADLE"; then
    if grep -q 'versionCode = 17' "$GRADLE" && \
       grep -q 'versionName = "1.4.10"' "$GRADLE"; then
        echo "Note: v1.4.10 gradle file found -- stale checkout, continuing."
    else
        echo "FATAL: $GRADLE is neither v1.4.12 nor v1.4.10."
        exit 1
    fi
fi

# If the installed-version display is missing, the settings file must
# be exactly the plain v1.4.10 one before it can be patched.
if ! grep -q 'appVersion' "$SETTINGS" 2>/dev/null; then
    verify "$SETTINGS" 4b11eb1af66e3fcf5ae6c9dac1f49dd8eb5e6ad2e51d0d745efdbda1c41804f5
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
SETTINGS = "app/src/main/java/com/ffmux/app/ui/settings/SettingsScreen.kt"

# =====================================================================
# HomeScreen.kt -- pencil rebuilt from scratch, preview untruncated
# =====================================================================
home_pairs = [
    ("""import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
""",
     """import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
""", 1),
    ("""                // Both the Author field and the pencil are pinned to the
                // same explicit 56dp: the field gets a fixed height and the
                // pencil is a plain 56x56 box without IconButton internals,
                // so the two outlines render pixel-flush and the button is
                // a perfect 1:1 square on every density and font scale.
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    OutlinedTextField(
                        value = uploader,
                        onValueChange = onUploaderChange,
                        modifier = Modifier
                            .weight(1f)
                            .height(56.dp),
                        label = { Text("Author") },
                        singleLine = true,
                        textStyle = MaterialTheme.typography.bodyMedium,
                        shape = MaterialTheme.shapes.small
                    )
                    Spacer(Modifier.width(8.dp))
                    val pencilInteraction = remember { MutableInteractionSource() }
                    Box(
                        modifier = rememberPressScale(pencilInteraction)
                            .size(56.dp)
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
     """                // The pencil is rebuilt from scratch: the row takes its
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
""", 1),
    ("""                OutlinedTextField(
                    value = text,
                    onValueChange = { text = it },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("File name") },
                    singleLine = true,
                    textStyle = MaterialTheme.typography.titleMedium,
                    shape = MaterialTheme.shapes.small
                )
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
                Spacer(Modifier.height(12.dp))
                Text(
                    "Output template fields",
                    style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Spacer(Modifier.height(8.dp))
                FlowRow(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    templateTokens.forEach { entry ->
                        TemplateTokenChip(
                            label = entry.label,
                            selected = entry.token in text,
                            onClick = { toggleToken(entry.token) }
                        )
                    }
                }
                // Whatever height is left over collects here, keeping the
                // action row pinned to the bottom of the dialog.
                Spacer(Modifier.weight(1f))
                Spacer(Modifier.height(10.dp))
""",
     """                // The whole middle of the dialog -- the file name field,
                // the live "Saved as" preview and the template field chips
                // -- scrolls together as one block: however many fields
                // are toggled on and however long the previewed file name
                // gets, every line of it stays readable and the action row
                // stays pinned to the bottom of the dialog.
                Column(
                    modifier = Modifier
                        .weight(1f)
                        .verticalScroll(rememberScrollState())
                ) {
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
                            )
                        }
                    }
                    Spacer(Modifier.height(12.dp))
                    Text(
                        "Output template fields",
                        style = MaterialTheme.typography.labelLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Spacer(Modifier.height(8.dp))
                    FlowRow(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        templateTokens.forEach { entry ->
                            TemplateTokenChip(
                                label = entry.label,
                                selected = entry.token in text,
                                onClick = { toggleToken(entry.token) }
                            )
                        }
                    }
                }
                Spacer(Modifier.height(10.dp))
""", 1),
]

patch(HOME_KT, home_pairs)

# =====================================================================
# app/build.gradle.kts -- version bump (v1.4.12 or stale v1.4.10)
# =====================================================================
with open(GRADLE, "r", encoding="utf-8") as fh:
    g = fh.read()

if 'versionCode = 19' in g and 'versionName = "1.4.12"' in g:
    g = g.replace("versionCode = 19", "versionCode = 20", 1)
    g = g.replace('versionName = "1.4.12"', 'versionName = "1.4.13"', 1)
elif 'versionCode = 17' in g and 'versionName = "1.4.10"' in g:
    g = g.replace("versionCode = 17", "versionCode = 20", 1)
    g = g.replace('versionName = "1.4.10"', 'versionName = "1.4.13"', 1)
else:
    print("FATAL: gradle version lines not recognised")
    sys.exit(1)

with open(GRADLE, "w", encoding="utf-8") as fh:
    fh.write(g)

# =====================================================================
# SettingsScreen.kt -- keep the installed-version display present
# (already there since v1.4.12; applied only if missing)
# =====================================================================
with open(SETTINGS, "r", encoding="utf-8") as fh:
    s = fh.read()

if "appVersion" not in s:
    settings_pairs = [
        ("""import androidx.compose.runtime.getValue
""",
         """import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
""", 1),
        ("""import androidx.compose.ui.Modifier
""",
         """import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
""", 1),
        ("""import androidx.compose.ui.unit.dp
""",
         """import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
""", 1),
        ("""    val treeUri by viewModel.treeUri.collectAsStateWithLifecycle()
""",
         """    val treeUri by viewModel.treeUri.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val appVersion = remember {
        runCatching {
            context.packageManager.getPackageInfo(context.packageName, 0).versionName
        }.getOrNull() ?: "?"
    }
""", 1),
        ("""            }
            Spacer(Modifier.height(8.dp))
        }
    }
}
""",
         """            }
            Spacer(Modifier.height(8.dp))
            Text(
                "FFMux v$appVersion",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth()
            )
        }
    }
}
""", 1),
    ]
    patch(SETTINGS, settings_pairs)

print("All patches applied.")
PYEOF

echo "Patches applied."

# ---------------------------------------------------------------------
# Output verification.
# ---------------------------------------------------------------------
verify "$HOME_KT"  cb2391e083a824e0ae93002967f9ece364c3fde2cacf8527968cddc692bff79f
verify "$GRADLE"   0cdcb92501d4b2f71f6f6faa1ba8a394cb1b2bb6cfe93d9203ad8d87cfeff4b5
verify "$SETTINGS" 846cd9a2814023b14e2a8dc3e0d3846a2f4f22c6a75c28d4c106a43e8586896f

grep -q 'IntrinsicSize.Min' "$HOME_KT" || { echo "FATAL: pencil rewrite missing"; exit 1; }
grep -q 'versionCode = 20' "$GRADLE" || { echo "FATAL: versionCode not bumped"; exit 1; }
grep -q 'appVersion' "$SETTINGS" || { echo "FATAL: version display missing"; exit 1; }
if grep -q 'maxLines = 2' "$HOME_KT"; then
    echo "FATAL: truncated preview still present"
    exit 1
fi

echo "Patch 20 applied cleanly (v1.4.13, versionCode 20)."
exit 0
