#!/usr/bin/env bash
set -euo pipefail

# =====================================================================
# FFMux patch 19  ->  v1.4.12 (versionCode 19)
#
# Same content as patch 18, except it no longer edits
# .github/workflows/build.yml.  Patch 18 applied cleanly, but its
# push was rejected: GitHub forbids the CI bot (GITHUB_TOKEN) from
# updating workflow files, and that permission cannot be granted.
# The workflow change is applied once, by hand, through the GitHub
# web editor (see the chat instructions).
#
# 1. The Settings screen shows the installed app version
#    ("FFMux v1.4.12") at the bottom, so it is always clear which
#    build is actually running on the phone.
# 2. Version bump 1.4.10/17 -> 1.4.12/19.
#
# Safe mode: sha256 baselines are verified before and after, every
# replacement is anchored and counted, and the run is idempotent.
# =====================================================================

cd "$(dirname "$0")"

echo "== FFMux patch 19 (v1.4.12) =="

SETTINGS="app/src/main/java/com/ffmux/app/ui/settings/SettingsScreen.kt"
GRADLE="app/build.gradle.kts"

# ---------------------------------------------------------------------
# Already patched?  Then this is a no-op.
# ---------------------------------------------------------------------
if grep -q 'versionName = "1.4.12"' "$GRADLE" 2>/dev/null && \
   grep -q 'appVersion' "$SETTINGS" 2>/dev/null; then
    echo "Already patched -- nothing to do."
    exit 0
fi

# ---------------------------------------------------------------------
# Baseline check: the tree must be exactly v1.4.10 (post patch 17).
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
        echo "The repository is not in the expected v1.4.10 state."
        exit 1
    fi
}

verify "$SETTINGS" 4b11eb1af66e3fcf5ae6c9dac1f49dd8eb5e6ad2e51d0d745efdbda1c41804f5
verify "$GRADLE"   7ade30858e256471db345f47455656cab36396b8c2388200c03c8cb8c237a328

echo "Baselines verified (v1.4.10)."

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
# SettingsScreen.kt -- show the app version at the bottom
# =====================================================================
SETTINGS = "app/src/main/java/com/ffmux/app/ui/settings/SettingsScreen.kt"

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

# =====================================================================
# app/build.gradle.kts -- version bump
# =====================================================================
GRADLE = "app/build.gradle.kts"

gradle_pairs = [
    ("""versionCode = 17""",
     """versionCode = 19""", 1),
    ('versionName = "1.4.10"',
     'versionName = "1.4.12"', 1),
]

patch(GRADLE, gradle_pairs)

print("All patches applied.")
PYEOF

echo "Patches applied."

# ---------------------------------------------------------------------
# Output verification: the patched tree must hash exactly to the
# reviewed v1.4.12 state.
# ---------------------------------------------------------------------
verify "$SETTINGS" 846cd9a2814023b14e2a8dc3e0d3846a2f4f22c6a75c28d4c106a43e8586896f
verify "$GRADLE"   31bcb36c04149a5e1948ae86af34e12c66e06b10593ed0f29df65513ed1beabb

grep -q 'appVersion' "$SETTINGS" || { echo "FATAL: version display missing"; exit 1; }
grep -q 'versionCode = 19' "$GRADLE" || { echo "FATAL: versionCode not bumped"; exit 1; }

# ---------------------------------------------------------------------
# Reminder (informational only): the workflow edit is manual now.
# ---------------------------------------------------------------------
if [ -f .github/workflows/build.yml ] && \
   grep -q 'Publish GitHub release on tag' .github/workflows/build.yml 2>/dev/null; then
    echo "NOTE: build.yml still has the old tag-only release step."
    echo "      Apply the manual build.yml edit (from the chat) so the"
    echo "      APK shows up on the Releases page."
fi

echo "Patch 19 applied cleanly (v1.4.12, versionCode 19)."
exit 0
