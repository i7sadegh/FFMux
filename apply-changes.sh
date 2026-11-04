#!/usr/bin/env bash
set -euo pipefail

# =====================================================================
# FFMux patch 17  ->  v1.4.10 (versionCode 17)
#
# Hotfix for the v1.4.9 build: the CA bundle refresher added in
# patch 16 (CaBundleFixer) declared its downloadTo helper with an
# expression body ("fun ... = try { ... }") but used an early
# "return false" inside it, which Kotlin rejects with
#   "Returns are prohibited for functions with an expression body"
# The helper now uses a regular block body; behaviour is identical.
#
# Safe mode: sha256 baselines are verified before and after, the
# replacement is anchored and counted, the run is idempotent, and
# the version is bumped only when the tree actually changed.
# =====================================================================

cd "$(dirname "$0")"

echo "== FFMux patch 17 (v1.4.10) =="

ENGINE="app/src/main/java/com/ffmux/app/engine/YtDlpEngine.kt"
GRADLE="app/build.gradle.kts"

# ---------------------------------------------------------------------
# Already patched?  Then this is a no-op.
# ---------------------------------------------------------------------
if grep -q 'versionName = "1.4.10"' "$GRADLE" 2>/dev/null && \
   grep -q 'private fun downloadTo(url: String, target: File): Boolean {' "$ENGINE" 2>/dev/null; then
    echo "Already patched -- nothing to do."
    exit 0
fi

# ---------------------------------------------------------------------
# Baseline check: the tree must be exactly v1.4.9 (post patch 16).
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
        echo "The repository is not in the expected v1.4.9 state."
        exit 1
    fi
}

verify "$ENGINE" fc2bab5992255a0163ffa5288bef8d6987c698568b6dc7616b55bd07020eaab0
verify "$GRADLE"  0d491cc7570e25963c64deac67afbf758e8663c7870a0514ef739486ce2299d5

echo "Baselines verified (v1.4.9)."

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
# YtDlpEngine.kt -- downloadTo: expression body -> block body
# =====================================================================
ENGINE = "app/src/main/java/com/ffmux/app/engine/YtDlpEngine.kt"

engine_pairs = []

engine_pairs.append((
"""    private fun downloadTo(url: String, target: File): Boolean = try {
        val connection = URL(url).openConnection() as HttpURLConnection
        connection.connectTimeout = 15000
        connection.readTimeout = 30000
        connection.instanceFollowRedirects = true
        if (connection.responseCode != 200) {
            connection.disconnect()
            return false
        }
        connection.inputStream.use { input ->
            target.outputStream().use { output -> input.copyTo(output) }
        }
        connection.disconnect()
        target.length() > 100_000
    } catch (e: Exception) {
        runCatching { target.delete() }
        false
    }
""",
"""    private fun downloadTo(url: String, target: File): Boolean {
        return try {
            val connection = URL(url).openConnection() as HttpURLConnection
            connection.connectTimeout = 15000
            connection.readTimeout = 30000
            connection.instanceFollowRedirects = true
            if (connection.responseCode != 200) {
                connection.disconnect()
                return false
            }
            connection.inputStream.use { input ->
                target.outputStream().use { output -> input.copyTo(output) }
            }
            connection.disconnect()
            target.length() > 100_000
        } catch (e: Exception) {
            runCatching { target.delete() }
            false
        }
    }
""", 1))

patch(ENGINE, engine_pairs)

# =====================================================================
# app/build.gradle.kts -- version bump
# =====================================================================
GRADLE = "app/build.gradle.kts"

gradle_pairs = [
    ("versionCode = 16", "versionCode = 17", 1),
    ('versionName = "1.4.9"', 'versionName = "1.4.10"', 1),
]

patch(GRADLE, gradle_pairs)

print("All patches applied.")
PYEOF

echo "Patches applied."

# ---------------------------------------------------------------------
# Output verification: the patched tree must hash exactly to the
# reviewed v1.4.10 state.
# ---------------------------------------------------------------------
verify "$ENGINE" 287fac8cf3b7f9e443fe4819116745df69297b16dae138bacb69a44d966405e0
verify "$GRADLE"  7ade30858e256471db345f47455656cab36396b8c2388200c03c8cb8c237a328

# ---------------------------------------------------------------------
# Feature sanity checks
# ---------------------------------------------------------------------
grep -q 'private fun downloadTo(url: String, target: File): Boolean {' "$ENGINE" || { echo "FATAL: block body missing"; exit 1; }
if grep -q 'downloadTo(url: String, target: File): Boolean = try' "$ENGINE"; then
    echo "FATAL: expression body still present"
    exit 1
fi
grep -q 'versionCode = 17' "$GRADLE" || { echo "FATAL: versionCode not bumped"; exit 1; }

echo "Patch 17 applied cleanly (v1.4.10, versionCode 17)."
exit 0
