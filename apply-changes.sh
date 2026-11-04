#!/usr/bin/env bash
set -euo pipefail

# =====================================================================
# FFMux patch 18  ->  v1.4.11 (versionCode 18)
#
# 1. The Settings screen now shows the installed app version
#    ("FFMux v1.4.11") at the bottom, so it is always clear which
#    build is actually running on the phone.
# 2. CI now publishes a GitHub Release with the APK on every
#    successful build (the old step only ran on v* tags, which never
#    happen). The APK can then be downloaded straight from the
#    Releases page and installed -- no zip extraction needed.
# 3. Version bump.
#
# Safe mode: sha256 baselines are verified before and after, every
# replacement is anchored and counted, the run is idempotent, and
# the version is bumped only when the tree actually changed.
# =====================================================================

cd "$(dirname "$0")"

echo "== FFMux patch 18 (v1.4.11) =="

SETTINGS="app/src/main/java/com/ffmux/app/ui/settings/SettingsScreen.kt"
WORKFLOW=".github/workflows/build.yml"
GRADLE="app/build.gradle.kts"

# ---------------------------------------------------------------------
# Already patched?  Then this is a no-op.
# ---------------------------------------------------------------------
if grep -q 'versionName = "1.4.11"' "$GRADLE" 2>/dev/null && \
   grep -q 'appVersion' "$SETTINGS" 2>/dev/null && \
   grep -q 'tag_name: v${{ steps.appver.outputs.version }}' "$WORKFLOW" 2>/dev/null; then
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
verify "$WORKFLOW" 0eed1d79aafe27afe0f528dd1c6fa3b6b02011c24d942b88b5894a256cd48572
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

settings_pairs = []

settings_pairs.append((
"""import androidx.compose.runtime.getValue
""",
"""import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
""", 1))

settings_pairs.append((
"""import androidx.compose.ui.Modifier
""",
"""import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
""", 1))

settings_pairs.append((
"""import androidx.compose.ui.unit.dp
""",
"""import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
""", 1))

settings_pairs.append((
"""    val treeUri by viewModel.treeUri.collectAsStateWithLifecycle()
""",
"""    val treeUri by viewModel.treeUri.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val appVersion = remember {
        runCatching {
            context.packageManager.getPackageInfo(context.packageName, 0).versionName
        }.getOrNull() ?: "?"
    }
""", 1))

settings_pairs.append((
"""            }
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
""", 1))

patch(SETTINGS, settings_pairs)

# =====================================================================
# build.yml -- publish a release with the APK on every build
# =====================================================================
WORKFLOW = ".github/workflows/build.yml"

workflow_pairs = []

workflow_pairs.append((
"""      - name: Publish GitHub release on tag
        if: startsWith(github.ref, 'refs/tags/v')
        uses: softprops/action-gh-release@v2
        with:
          files: app/build/outputs/apk/release/app-release.apk
""",
"""      - name: Read app version
        id: appver
        run: echo "version=$(grep -oP 'versionName = "\\K[^"]+' app/build.gradle.kts)" >> "$GITHUB_OUTPUT"

      - name: Publish GitHub release
        uses: softprops/action-gh-release@v2
        with:
          tag_name: v${{ steps.appver.outputs.version }}
          name: FFMux v${{ steps.appver.outputs.version }}
          files: app/build/outputs/apk/release/app-release.apk
""", 1))

patch(WORKFLOW, workflow_pairs)

# =====================================================================
# app/build.gradle.kts -- version bump
# =====================================================================
GRADLE = "app/build.gradle.kts"

gradle_pairs = [
    ("versionCode = 17", "versionCode = 18", 1),
    ('versionName = "1.4.10"', 'versionName = "1.4.11"', 1),
]

patch(GRADLE, gradle_pairs)

print("All patches applied.")
PYEOF

echo "Patches applied."

# ---------------------------------------------------------------------
# Output verification: the patched tree must hash exactly to the
# reviewed v1.4.11 state.
# ---------------------------------------------------------------------
verify "$SETTINGS" 846cd9a2814023b14e2a8dc3e0d3846a2f4f22c6a75c28d4c106a43e8586896f
verify "$WORKFLOW" 42ae7b90f411a22383cd7b541fcae5cb823a2887e606f17b4655ceb96e3882fd
verify "$GRADLE"   866ce352268ad4d0d4789807020c46d314b4a55efc6b37ea7e8b18db211747ca

# ---------------------------------------------------------------------
# Feature sanity checks
# ---------------------------------------------------------------------
grep -q 'appVersion' "$SETTINGS" || { echo "FATAL: version display missing"; exit 1; }
grep -q 'Publish GitHub release' "$WORKFLOW" || { echo "FATAL: release step missing"; exit 1; }
if grep -q "Publish GitHub release on tag" "$WORKFLOW"; then
    echo "FATAL: old tag-only release step still present"
    exit 1
fi
grep -q 'versionCode = 18' "$GRADLE" || { echo "FATAL: versionCode not bumped"; exit 1; }

echo "Patch 18 applied cleanly (v1.4.11, versionCode 18)."
exit 0
