#!/usr/bin/env bash
set -euo pipefail

# =====================================================================
# FFMux patch 16  ->  v1.4.9 (versionCode 16)
#
# 1. Pencil button next to the Author field: both the field and the
#    button are now pinned to the same explicit 56dp -- the button is a
#    plain 56x56 box (no IconButton internals), so its outline is
#    pixel-flush with the text field border and perfectly 1:1.
# 2. Recording duration dialog: presets are laid out in TWO columns
#    with a bit more breathing room between the rows.
# 3. Filename template dialog: the "Saved as" preview box moved right
#    under the input, and the template fields are now capsule chips in
#    a flowing multi-row layout, identical to the option chips on the
#    Home screen -- toggling a chip refreshes the preview instantly.
# 4. SSL "certificate verify failed" fix: the CA bundle of the bundled
#    Python is refreshed from the current Mozilla list (curl.se) once
#    it is older than 30 days, and any fetch/download that fails on
#    certificate verification retries once with a freshly downloaded
#    bundle.
#
# Safe mode: sha256 baselines are verified before and after, every
# replacement is anchored and counted, the run is idempotent, and the
# version is bumped only when the tree actually changed.
# =====================================================================

cd "$(dirname "$0")"

echo "== FFMux patch 16 (v1.4.9) =="

HOME_SCREEN="app/src/main/java/com/ffmux/app/ui/home/HomeScreen.kt"
ENGINE="app/src/main/java/com/ffmux/app/engine/YtDlpEngine.kt"
GRAPH="app/src/main/java/com/ffmux/app/Graph.kt"
GRADLE="app/build.gradle.kts"

# ---------------------------------------------------------------------
# Already patched?  Then this is a no-op.
# ---------------------------------------------------------------------
if grep -q 'versionName = "1.4.9"' "$GRADLE" 2>/dev/null && \
   grep -q 'TemplateTokenChip' "$HOME_SCREEN" 2>/dev/null && \
   grep -q 'CaBundleFixer' "$ENGINE" 2>/dev/null; then
    echo "Already patched -- nothing to do."
    exit 0
fi

# ---------------------------------------------------------------------
# Baseline check: the tree must be exactly v1.4.8.
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
        echo "The repository is not in the expected v1.4.8 state."
        exit 1
    fi
}

verify "$HOME_SCREEN" dfc8d0f18451fb9cb02e957d56c8e7b912dcc6ff911b2e8908f8335da22f8b9f
verify "$ENGINE"     66a4e183e902cb8407acb2a705dd90a2efeb812d2e4f925cf7c2135f4c823c39
verify "$GRAPH"      4f0ce4eff80189fc9a5d86a474065deff56cb0334bbb85b03a8a451cfc6ee4de
verify "$GRADLE"     ce7ee2833a72b8cee3660890d322594ca8c1b1a0ea6412facda54eb5b6cc3b8f

echo "Baselines verified (v1.4.8)."

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
# HomeScreen.kt
# =====================================================================
HOME_SCREEN = "app/src/main/java/com/ffmux/app/ui/home/HomeScreen.kt"

home_pairs = []

# ---- imports: drop the measurement/intrinsics machinery, add the
#      plain-Box pencil and the chip icons ----
home_pairs.append((
    "import androidx.compose.foundation.layout.IntrinsicSize\n", "", 1))
home_pairs.append((
    "import androidx.compose.ui.layout.onSizeChanged\n", "", 1))
home_pairs.append((
    "import androidx.compose.ui.platform.LocalDensity\n", "", 1))
home_pairs.append((
    "import androidx.compose.foundation.border\n",
    "import androidx.compose.foundation.border\n"
    "import androidx.compose.foundation.clickable\n", 1))
home_pairs.append((
    "import androidx.compose.material.icons.rounded.ArrowDropDown\n",
    "import androidx.compose.material.icons.rounded.Add\n"
    "import androidx.compose.material.icons.rounded.ArrowDropDown\n", 1))
home_pairs.append((
    "import androidx.compose.material.icons.rounded.Audiotrack\n",
    "import androidx.compose.material.icons.rounded.Audiotrack\n"
    "import androidx.compose.material.icons.rounded.Check\n", 1))
home_pairs.append((
    "import androidx.compose.material3.RadioButton\n",
    "import androidx.compose.material3.RadioButton\n"
    "import androidx.compose.material3.ripple\n", 1))
home_pairs.append((
    "import androidx.compose.ui.platform.LocalConfiguration\n",
    "import androidx.compose.ui.platform.LocalConfiguration\n"
    "import androidx.compose.ui.semantics.Role\n", 1))

# ---- 1. pencil: explicit 56dp on both sides, plain Box button ----
home_pairs.append((
"""                Spacer(Modifier.height(8.dp))
                // The pencil is sized to the exact height the Author field
                // renders at, measured live after layout: the two are always
                // flush on every density and font scale, and the button is a
                // perfect 1:1 square -- it no longer sticks out above the row.
                val density = LocalDensity.current
                var authorHeightPx by remember { mutableStateOf<Int?>(null) }
                val pencilSize = authorHeightPx?.let { with(density) { it.toDp() } } ?: 56.dp
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    OutlinedTextField(
                        value = uploader,
                        onValueChange = onUploaderChange,
                        modifier = Modifier
                            .weight(1f)
                            .onSizeChanged { authorHeightPx = it.height },
                        label = { Text("Author") },
                        singleLine = true,
                        textStyle = MaterialTheme.typography.bodyMedium,
                        shape = MaterialTheme.shapes.small
                    )
                    Spacer(Modifier.width(8.dp))
                    val pencilInteraction = remember { MutableInteractionSource() }
                    FilledTonalIconButton(
                        onClick = { showTemplate = true },
                        interactionSource = pencilInteraction,
                        modifier = rememberPressScale(pencilInteraction)
                            .size(pencilSize),
                        shape = MaterialTheme.shapes.small
                    ) {
                        Icon(
                            imageVector = Icons.Outlined.Edit,
                            contentDescription = "Filename template"
                        )
                    }
                }
""",
"""                Spacer(Modifier.height(8.dp))
                // Both the Author field and the pencil are pinned to the
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
""", 1))

# ---- 2. duration dialog: presets in two columns with more air ----
home_pairs.append((
"""                durationPresets.forEach { preset ->
                    // Compact rows: the radio is capped at 24dp so its 48dp
                    // touch padding no longer doubles the height of every
                    // line -- the whole row stays the tap target.
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(MaterialTheme.shapes.extraSmall)
                            .selectable(selected = picked == preset, onClick = { picked = preset })
                            .padding(vertical = 2.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        RadioButton(
                            selected = picked == preset,
                            onClick = { picked = preset },
                            modifier = Modifier.size(24.dp)
                        )
                        Spacer(Modifier.width(10.dp))
                        Text(
                            text = if (preset == 0) "No limit" else durationText(preset),
                            style = MaterialTheme.typography.bodyLarge
                        )
                    }
                }
""",
"""                // Two columns of presets: each pair fills the width
                // evenly and the rows get a little air back, so the list
                // stays compact without the cramped single-column look.
                durationPresets.chunked(2).forEach { rowPresets ->
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(10.dp)
                    ) {
                        rowPresets.forEach { preset ->
                            Row(
                                modifier = Modifier
                                    .weight(1f)
                                    .clip(MaterialTheme.shapes.extraSmall)
                                    .selectable(
                                        selected = picked == preset,
                                        onClick = { picked = preset }
                                    )
                                    .padding(vertical = 5.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                RadioButton(
                                    selected = picked == preset,
                                    onClick = { picked = preset },
                                    modifier = Modifier.size(22.dp)
                                )
                                Spacer(Modifier.width(8.dp))
                                Text(
                                    text = if (preset == 0) "No limit" else durationText(preset),
                                    style = MaterialTheme.typography.bodyLarge
                                )
                            }
                        }
                        if (rowPresets.size == 1) Spacer(Modifier.weight(1f))
                    }
                }
""", 1))

# custom-minutes row: matched through its unique picked == -1 anchor
home_pairs.append((
"""                        .selectable(selected = picked == -1, onClick = { picked = -1 })
                        .padding(vertical = 2.dp),
""",
"""                        .selectable(selected = picked == -1, onClick = { picked = -1 })
                        .padding(vertical = 5.dp),
""", 1))
home_pairs.append((
"""                    RadioButton(
                        selected = picked == -1,
                        onClick = { picked = -1 },
                        modifier = Modifier.size(24.dp)
                    )
""",
"""                    RadioButton(
                        selected = picked == -1,
                        onClick = { picked = -1 },
                        modifier = Modifier.size(22.dp)
                    )
""", 1))

# ---- 3. template dialog: OptIn for FlowRow ----
home_pairs.append((
"""@Composable
private fun FilenameTemplateDialog(
""",
"""@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun FilenameTemplateDialog(
""", 1))

# ---- 3. template dialog: preview box under the input, chips below ----
home_pairs.append((
"""                Spacer(Modifier.height(12.dp))
                Text(
                    "Output template fields",
                    style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Spacer(Modifier.height(4.dp))
                Surface(
                    modifier = Modifier
                        .fillMaxWidth()
                        .weight(1f),
                    shape = MaterialTheme.shapes.small,
                    color = MaterialTheme.colorScheme.surfaceContainerHighest
                ) {
                    Column(
                        modifier = Modifier
                            .fillMaxSize()
                            .verticalScroll(rememberScrollState())
                            .padding(horizontal = 6.dp, vertical = 2.dp)
                    ) {
                        templateTokens.forEach { entry ->
                            val checked = entry.token in text
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clip(MaterialTheme.shapes.extraSmall)
                                    .selectable(
                                        selected = checked,
                                        onClick = { toggleToken(entry.token) }
                                    )
                                    .padding(vertical = 2.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Checkbox(
                                    checked = checked,
                                    onCheckedChange = { toggleToken(entry.token) }
                                )
                                Column(
                                    modifier = Modifier.weight(1f),
                                    horizontalAlignment = Alignment.Start
                                ) {
                                    Text(
                                        text = entry.label,
                                        style = MaterialTheme.typography.bodyLarge
                                    )
                                    Text(
                                        text = entry.hint,
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                }
                                Text(
                                    text = entry.token,
                                    style = MaterialTheme.typography.bodySmall.copy(
                                        fontFamily = FontFamily.Monospace
                                    ),
                                    color = MaterialTheme.colorScheme.primary
                                )
                            }
                        }
                    }
                }
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
                Spacer(Modifier.height(10.dp))
""",
"""                Spacer(Modifier.height(12.dp))
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
""", 1))

# ---- 3. the capsule chip composable, right before the preview helper ----
home_pairs.append((
"""/**
 * The "Saved as" preview: the fields this video already knows are
""",
"""/**
 * One capsule toggle of the filename template dialog. Drawn exactly like
 * the option chips under the quality cards on the Home screen: a pill
 * with an animated outline and container color whose leading icon flips
 * between a plus and a check as the field goes in and out of the name.
 */
@Composable
private fun TemplateTokenChip(
    label: String,
    selected: Boolean,
    onClick: () -> Unit
) {
    val animatedOutline by animateColorAsState(
        targetValue = if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outlineVariant,
        animationSpec = tween(100), label = "tokenOutline"
    )
    val animatedContainer by animateColorAsState(
        targetValue = if (selected) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surface,
        animationSpec = tween(100), label = "tokenContainer"
    )
    val animatedTitle by animateColorAsState(
        targetValue = if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface,
        animationSpec = tween(100), label = "tokenTitle"
    )
    Row(
        modifier = Modifier
            .clip(androidx.compose.foundation.shape.CircleShape)
            .selectable(selected = selected, onClick = onClick)
            .border(1.dp, animatedOutline, androidx.compose.foundation.shape.CircleShape)
            .background(animatedContainer)
            .padding(start = 14.dp, end = 18.dp, top = 10.dp, bottom = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Icon(
            imageVector = if (selected) Icons.Rounded.Check else Icons.Rounded.Add,
            contentDescription = null,
            tint = animatedOutline,
            modifier = Modifier.size(16.dp)
        )
        Text(
            text = label,
            style = MaterialTheme.typography.labelLarge,
            color = animatedTitle
        )
    }
}

/**
 * The "Saved as" preview: the fields this video already knows are
""", 1))

patch(HOME_SCREEN, home_pairs)

# =====================================================================
# YtDlpEngine.kt -- CA bundle refresh + one retry on certificate errors
# =====================================================================
ENGINE = "app/src/main/java/com/ffmux/app/engine/YtDlpEngine.kt"

engine_pairs = []

engine_pairs.append((
"""import kotlinx.serialization.json.Json
""",
"""import kotlinx.serialization.json.Json
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
""", 1))

engine_pairs.append((
"""    /** Fetches metadata for a single video (equivalent of `yt-dlp -J`). */
    suspend fun fetchInfo(url: String): VideoInfo = withContext(Dispatchers.IO) {
        val request = YoutubeDLRequest(url).apply {
            addOption("-J")
            addOption("--no-playlist")
            addOption("--retries", 10)
            addOption("--socket-timeout", 30)
        }
        val response = YoutubeDL.getInstance().execute(request)
        json.decodeFromString(response.out)
    }
""",
"""    /**
     * Fetches metadata for a single video (equivalent of `yt-dlp -J`).
     * A certificate verification failure triggers one retry after the
     * CA bundle of the bundled Python has been refreshed, so a stale
     * root store never blocks a site for good.
     */
    suspend fun fetchInfo(url: String): VideoInfo = withContext(Dispatchers.IO) {
        try {
            executeInfo(url)
        } catch (e: Exception) {
            if (isCertificateError(e.message) && CaBundleFixer.refresh(appContext)) {
                executeInfo(url)
            } else {
                throw e
            }
        }
    }

    private fun executeInfo(url: String): VideoInfo {
        val request = YoutubeDLRequest(url).apply {
            addOption("-J")
            addOption("--no-playlist")
            addOption("--retries", 10)
            addOption("--socket-timeout", 30)
        }
        val response = YoutubeDL.getInstance().execute(request)
        return json.decodeFromString(response.out)
    }
""", 1))

engine_pairs.append((
"""    fun download(
        url: String,
        selector: String,
        extraArgs: String,
        processId: String,
        outputTemplate: String,
        onProgress: (Float, Long, String) -> Unit
    ) {
        val request = YoutubeDLRequest(url).apply {
            addOption("--no-playlist")
            addOption("-f", selector)
            addOption("-o", outputTemplate)
            addOption("--no-mtime")
            addOption("--retries", 10)
            addOption("--fragment-retries", 10)
            addOption("--socket-timeout", 30)
            if (selector.contains('+')) {
                addOption("--merge-output-format", "mp4/mkv")
            }
            applyExtraArgs(extraArgs)
        }
        YoutubeDL.getInstance().execute(request, processId) { progress, eta, line ->
            onProgress(progress, eta, line)
        }
    }
""",
"""    fun download(
        url: String,
        selector: String,
        extraArgs: String,
        processId: String,
        outputTemplate: String,
        onProgress: (Float, Long, String) -> Unit
    ) {
        try {
            executeDownload(url, selector, extraArgs, processId, outputTemplate, onProgress)
        } catch (e: Exception) {
            // Same safety net as fetchInfo: refresh the CA bundle once
            // and run the request again, so one stale certificate list
            // cannot kill an otherwise healthy download.
            if (isCertificateError(e.message) && CaBundleFixer.refresh(appContext)) {
                executeDownload(url, selector, extraArgs, processId, outputTemplate, onProgress)
            } else {
                throw e
            }
        }
    }

    private fun executeDownload(
        url: String,
        selector: String,
        extraArgs: String,
        processId: String,
        outputTemplate: String,
        onProgress: (Float, Long, String) -> Unit
    ) {
        val request = YoutubeDLRequest(url).apply {
            addOption("--no-playlist")
            addOption("-f", selector)
            addOption("-o", outputTemplate)
            addOption("--no-mtime")
            addOption("--retries", 10)
            addOption("--fragment-retries", 10)
            addOption("--socket-timeout", 30)
            if (selector.contains('+')) {
                addOption("--merge-output-format", "mp4/mkv")
            }
            applyExtraArgs(extraArgs)
        }
        YoutubeDL.getInstance().execute(request, processId) { progress, eta, line ->
            onProgress(progress, eta, line)
        }
    }

    /** True when a failure message is an HTTPS certificate problem. */
    private fun isCertificateError(message: String?): Boolean =
        message?.contains("CERTIFICATE_VERIFY_FAILED") == true ||
            message?.contains("certificate verify failed") == true
""", 1))

# CA bundle fixer appended after the engine class
engine_pairs.append((
"""        private fun sizeText(bytes: Long?): String? {
            if (bytes == null) return null
            val mb = bytes / 1048576.0
            return when {
                mb >= 1024.0 -> String.format("%.1f GB", mb / 1024.0)
                mb >= 100.0 -> String.format("%.0f MB", mb)
                mb >= 1.0 -> String.format("%.1f MB", mb)
                else -> String.format("%.0f KB", bytes / 1024.0)
            }
        }
    }
}
""",
"""        private fun sizeText(bytes: Long?): String? {
            if (bytes == null) return null
            val mb = bytes / 1048576.0
            return when {
                mb >= 1024.0 -> String.format("%.1f GB", mb / 1024.0)
                mb >= 100.0 -> String.format("%.0f MB", mb)
                mb >= 1.0 -> String.format("%.1f MB", mb)
                else -> String.format("%.0f KB", bytes / 1024.0)
            }
        }
    }
}

/**
 * Replaces the CA certificate bundle the bundled Python verifies HTTPS
 * connections with. youtubedl-android ships a snapshot of the Mozilla
 * root store; once it ages, yt-dlp rejects sites whose certificates
 * were issued by newer authorities with
 * "unable to get local issuer certificate". The bundle lives in
 * writable app storage, so the current list can simply be downloaded
 * over it (the download itself uses the healthy Android system trust
 * store, not the stale file).
 */
internal object CaBundleFixer {

    /** Refresh the bundle when the shipped one is older than this. */
    private const val STALE_AFTER_MS = 30L * 24 * 60 * 60 * 1000L

    /** Mirror of https://curl.se/ca/cacert.pem on GitHub, as a fallback. */
    private val SOURCES = listOf(
        "https://curl.se/ca/cacert.pem",
        "https://raw.githubusercontent.com/curl/curl-www/ca/cacert.pem"
    )

    /** The exact file youtubedl-android points SSL_CERT_FILE at. */
    fun certFile(context: Context): File =
        File(
            File(context.noBackupFilesDir, "youtubedl-android"),
            "packages/python/usr/etc/tls/cert.pem"
        )

    /** Refreshes the bundle when it is missing or older than 30 days. */
    fun refreshIfStale(context: Context) {
        val target = certFile(context)
        if (target.exists() &&
            System.currentTimeMillis() - target.lastModified() < STALE_AFTER_MS
        ) {
            return
        }
        refresh(context)
    }

    /** Downloads the current Mozilla CA list into the engine's cert path. */
    fun refresh(context: Context): Boolean {
        val target = certFile(context)
        val dir = target.parentFile ?: return false
        if (!dir.exists() && !dir.mkdirs()) return false
        val tmp = File(dir, "cert.pem.tmp")
        try {
            for (url in SOURCES) {
                if (downloadTo(url, tmp) && isPemBundle(tmp)) {
                    if (tmp.renameTo(target)) return true
                    // Some filesystems refuse the rename; copy instead.
                    try {
                        tmp.copyTo(target, overwrite = true)
                        tmp.delete()
                        return true
                    } catch (e: Exception) {
                        // try the next source
                    }
                }
                tmp.delete()
            }
        } catch (e: Exception) {
            runCatching { tmp.delete() }
            return false
        }
        return false
    }

    private fun downloadTo(url: String, target: File): Boolean = try {
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

    private fun isPemBundle(file: File): Boolean = try {
        file.readText().contains("-----BEGIN CERTIFICATE-----")
    } catch (e: Exception) {
        false
    }
}
""", 1))

patch(ENGINE, engine_pairs)

# =====================================================================
# Graph.kt -- refresh the CA bundle right after the engine is unpacked
# =====================================================================
GRAPH = "app/src/main/java/com/ffmux/app/Graph.kt"

graph_pairs = []

graph_pairs.append((
"""import com.ffmux.app.data.db.AppDatabase
""",
"""import com.ffmux.app.data.db.AppDatabase
import com.ffmux.app.engine.CaBundleFixer
""", 1))

graph_pairs.append((
"""                engineInit = appScope.async(Dispatchers.IO) {
                    YoutubeDL.getInstance().init(app)
                    runCatching { FFmpeg.getInstance().init(app) }
                    engineReady.value = true
                }
""",
"""                engineInit = appScope.async(Dispatchers.IO) {
                    YoutubeDL.getInstance().init(app)
                    runCatching { FFmpeg.getInstance().init(app) }
                    // Keep the HTTPS root store of the bundled Python
                    // fresh, so yt-dlp also trusts certificate authorities
                    // that were added after the library was built.
                    runCatching { CaBundleFixer.refreshIfStale(app) }
                    engineReady.value = true
                }
""", 1))

patch(GRAPH, graph_pairs)

# =====================================================================
# app/build.gradle.kts -- version bump
# =====================================================================
GRADLE = "app/build.gradle.kts"

gradle_pairs = [
    ("versionCode = 15", "versionCode = 16", 1),
    ('versionName = "1.4.8"', 'versionName = "1.4.9"', 1),
]

patch(GRADLE, gradle_pairs)

print("All patches applied.")
PYEOF

echo "Patches applied."

# ---------------------------------------------------------------------
# Output verification: the patched tree must hash exactly to the
# reviewed v1.4.9 state.
# ---------------------------------------------------------------------
verify "$HOME_SCREEN" a8a58406f40cbe3ee85a7d615fb5df0d50b45f48e7fe6d25f48f6da072c7baa5
verify "$ENGINE"      fc2bab5992255a0163ffa5288bef8d6987c698568b6dc7616b55bd07020eaab0
verify "$GRAPH"       84fde9c7079cf076be3f8bdce08a4aeb896ef3dfccb0d965fde76bf33d29b4d0
verify "$GRADLE"      0d491cc7570e25963c64deac67afbf758e8663c7870a0514ef739486ce2299d5

# ---------------------------------------------------------------------
# Feature sanity checks
# ---------------------------------------------------------------------
grep -q 'height(56.dp)' "$HOME_SCREEN" || { echo "FATAL: field height missing"; exit 1; }
grep -q 'size(56.dp)' "$HOME_SCREEN" || { echo "FATAL: pencil size missing"; exit 1; }
grep -q 'chunked(2)' "$HOME_SCREEN" || { echo "FATAL: two-column presets missing"; exit 1; }
grep -q 'TemplateTokenChip' "$HOME_SCREEN" || { echo "FATAL: template chips missing"; exit 1; }
grep -q 'CaBundleFixer' "$ENGINE" || { echo "FATAL: CA fixer missing"; exit 1; }
grep -q 'versionCode = 16' "$GRADLE" || { echo "FATAL: versionCode not bumped"; exit 1; }

echo "Patch 16 applied cleanly (v1.4.9, versionCode 16)."
exit 0
