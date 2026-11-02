#!/usr/bin/env bash
###############################################################################
# FFMux UI patches 1+2+3 -- cumulative, idempotent patcher.
# Run from the repository root:  bash apply-changes.sh
#
# Patch 1 (Nov 2, round 1):
#   1. Seal-style video info card (HomeScreen.kt): full-width 16:9
#      thumbnail inside an ElevatedCard, title (titleMedium, 2 lines)
#      and channel name (bodyMedium) under it, 12dp padding.
#   2. Duration badge on the thumbnail's bottom-end corner.
#   3. The About card is removed from the Settings screen.
#   4. Custom bottom navigation (AppRoot.kt): a secondaryContainer pill
#      (64x32dp) slides between tabs with a spring, and the selected
#      tab icon does a small squeeze-and-release bounce.
#
# Patch 2 (Nov 2, round 2):
#   5. Press ripple removed from the bottom bar tabs (no more gray
#      flash while touching an icon): selectable() now gets an explicit
#      interactionSource with indication = null.
#   6. Duration badge text enlarged and made screen-size aware: the font
#      size is 3.8% of the screen width, clamped to 12..18sp, medium
#      weight, roomier badge padding -- so every display gets a
#      proportional size instead of the old fixed 11sp.
#   7. Faster page switching: explicit NavHost crossfade of 150ms in /
#      100ms out (the navigation library default was a 700ms fade),
#      pill spring stiffness raised to Medium (settles in ~300ms
#      instead of ~0.8s), icon squeeze shortened from 400ms to 280ms.
#
# Patch 3 (Nov 2, round 3):
#   8. The name and the author under the thumbnail are now editable
#      (Title / Author fields, pencil icon on the title). The saved
#      file is named after the edited title; the edited author is kept
#      with the download entry.
#   9. The plain radio-button quality list becomes compact Seal-style
#      format cards, two per row (much smaller than Seal's cards):
#      container / fps / bitrate / estimated size on each card, Seal's
#      exact audio and video marks (Icons.Rounded.Videocam and
#      Icons.Rounded.Audiotrack) in the corner, animated selection
#      colors (100ms, like Seal).
#  10. A fixed "Best" card is always pinned above the qualities
#      (selector bestvideo*+bestaudio/best) and is selected by default.
#  11. Folds in the youtubedl-android 0.18.1 null-safety fix (repo
#      commit a99ed1b) so even a pre-fix tree compiles on Actions.
#
# Patch 4 (Nov 3, round 4):
#  12. Video and audio qualities are listed apart, Seal-style: every
#      stream is its own compact selectable card (format id,
#      resolution, fps, container, bitrate, size).
#  13. A video-only card and an audio card can be picked together and
#      are merged into one file (yt-dlp "id+id" with ffmpeg). Streams
#      that already carry both video and audio download as they are
#      (they show both marks, like Seal).
#  14. The download button is pinned under the scrolling list and
#      shows the estimated size of the file the current selection
#      will produce.
#
# Patch 5 (Nov 3, round 5):
#  15. The Home screen keeps the link, the info card and the format
#      selection after a download is queued -- coming back from the
#      Downloads tab no longer shows a blank, reset page.
#  16. Downloads survive flaky networks: yt-dlp retries 10 times per
#      file and per fragment with a 30s socket timeout (fixes
#      "[errno 104] connection reset by peer").
#  17. A terminal log: the Downloads screen gets a "Downloads" title
#      with a terminal button next to it; the dialog shows the exact
#      yt-dlp command and every output line of every download, colored
#      like a real terminal (so "postprocessing: conversion failed"
#      can be read in full before retrying).
#  18. Failed downloads get a retry button (re-queued with the same
#      link and the same format selector).
#  19. F-Droid style progress bar: dark-blue fill on a green track
#      with a blue dot at the end, "4.9 MiB / 9.6 MiB" on the left,
#      "51%" on the right, grey cancel button on the right.
#  20. Status bar icons follow the theme: dark icons on the light
#      theme, light icons on the dark theme.
#  21. Room schema v2: byte counters + terminal log columns, with a
#      real 1->2 migration (existing download history is kept).
#
# App version after this script: 1.3.0 (versionCode 6).
#
# Safe to run on: a fresh clone of the upstream repo, a tree that
# already carries patch 1, patches 1+2, patches 1+2+3, or this patch
# (everything skips). Aborts loudly, without writing, on any anchor
# mismatch.
#
# Files touched: HomeScreen.kt, HomeViewModel.kt, SettingsScreen.kt,
#                AppRoot.kt, YtDlpEngine.kt, Models.kt,
#                DownloadService.kt, DownloadEntity.kt,
#                AppDatabase.kt, DownloadDao.kt, Graph.kt,
#                DownloadsScreen.kt, DownloadsViewModel.kt, Theme.kt,
#                app/build.gradle.kts
###############################################################################
set -euo pipefail

if LC_ALL=C grep -qn '[^ -~]' "$0"; then
  echo "FATAL: non-ascii byte in this script"
  exit 1
fi

HOME_S="app/src/main/java/com/ffmux/app/ui/home/HomeScreen.kt"
VM_S="app/src/main/java/com/ffmux/app/ui/home/HomeViewModel.kt"
SET_S="app/src/main/java/com/ffmux/app/ui/settings/SettingsScreen.kt"
ROOT_S="app/src/main/java/com/ffmux/app/ui/AppRoot.kt"
ENG_S="app/src/main/java/com/ffmux/app/engine/YtDlpEngine.kt"
MOD_S="app/src/main/java/com/ffmux/app/engine/Models.kt"
SVC_S="app/src/main/java/com/ffmux/app/engine/DownloadService.kt"
ENT_S="app/src/main/java/com/ffmux/app/data/db/DownloadEntity.kt"
ADB_S="app/src/main/java/com/ffmux/app/data/db/AppDatabase.kt"
DAO_S="app/src/main/java/com/ffmux/app/data/db/DownloadDao.kt"
GR_S="app/src/main/java/com/ffmux/app/Graph.kt"
DLS_S="app/src/main/java/com/ffmux/app/ui/downloads/DownloadsScreen.kt"
DLV_S="app/src/main/java/com/ffmux/app/ui/downloads/DownloadsViewModel.kt"
THEME_S="app/src/main/java/com/ffmux/app/ui/theme/Theme.kt"
BUILD_G="app/build.gradle.kts"
for f in "$HOME_S" "$VM_S" "$SET_S" "$ROOT_S" "$ENG_S" "$MOD_S" "$SVC_S" \
         "$ENT_S" "$ADB_S" "$DAO_S" "$GR_S" "$DLS_S" "$DLV_S" "$THEME_S" \
         "$BUILD_G"; do
  if [ ! -f "$f" ]; then
    echo "FATAL: $f not found - run from the repository root"
    exit 1
  fi
done

echo "== patches 1+2+3+4+5: Seal card, split video/audio cards, sticky link, terminal log, F-Droid progress bar, retry, theme-aware status bar =="
python3 - <<'PYEOF'
import re
import sys

HOME_S = "app/src/main/java/com/ffmux/app/ui/home/HomeScreen.kt"
VM_S = "app/src/main/java/com/ffmux/app/ui/home/HomeViewModel.kt"
SET_S = "app/src/main/java/com/ffmux/app/ui/settings/SettingsScreen.kt"
ROOT_S = "app/src/main/java/com/ffmux/app/ui/AppRoot.kt"
ENG_S = "app/src/main/java/com/ffmux/app/engine/YtDlpEngine.kt"
MOD_S = "app/src/main/java/com/ffmux/app/engine/Models.kt"
SVC_S = "app/src/main/java/com/ffmux/app/engine/DownloadService.kt"
ENT_S = "app/src/main/java/com/ffmux/app/data/db/DownloadEntity.kt"
ADB_S = "app/src/main/java/com/ffmux/app/data/db/AppDatabase.kt"
DAO_S = "app/src/main/java/com/ffmux/app/data/db/DownloadDao.kt"
GR_S = "app/src/main/java/com/ffmux/app/Graph.kt"
DLS_S = "app/src/main/java/com/ffmux/app/ui/downloads/DownloadsScreen.kt"
DLV_S = "app/src/main/java/com/ffmux/app/ui/downloads/DownloadsViewModel.kt"
THEME_S = "app/src/main/java/com/ffmux/app/ui/theme/Theme.kt"
BUILD_G = "app/build.gradle.kts"

edits_applied = 0
edits_skipped = 0
FAILED = []

def rd(p):
    with open(p, encoding="utf-8") as f:
        return f.read()

def wr(p, s):
    with open(p, "w", encoding="utf-8", newline="") as f:
        f.write(s)

def apply_edit(path, old, new, label, already=None):
    """Single-site idempotent edit. Skip when the marker (default: the
    new text itself) is already present, fail loudly when the anchor is
    missing or ambiguous. A marker must be a string this edit itself
    creates and no later edit removes, so later patches can rewrite
    the same region without breaking re-runs."""
    global edits_applied, edits_skipped
    src = rd(path)
    if (already if already is not None else new) in src:
        edits_skipped += 1
        print("  [skip]    " + label)
        return
    n = src.count(old)
    if n != 1:
        FAILED.append(label + " (anchor count " + str(n) + ")")
        print("  [FAIL]    " + label + " (anchor count " + str(n) + ")")
        return
    wr(path, src.replace(old, new))
    edits_applied += 1
    print("  [applied] " + label)

# ===========================================================================
# PATCH 1
# ===========================================================================

# ---------------------------------------------------------------------------
# Edit 1: HomeScreen imports -- add Box / aspectRatio / ElevatedCard /
# Surface / Color, drop Card / RoundedCornerShape (only the old card used
# them).
# ---------------------------------------------------------------------------
OLD_HOME_IMPORTS = '''import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ContentPaste
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import coil.compose.AsyncImage
import com.ffmux.app.Graph
import com.ffmux.app.engine.VideoInfo
import com.ffmux.app.util.UrlUtils'''

NEW_HOME_IMPORTS = '''import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ContentPaste
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import coil.compose.AsyncImage
import com.ffmux.app.Graph
import com.ffmux.app.engine.VideoInfo
import com.ffmux.app.util.UrlUtils'''

apply_edit(HOME_S, OLD_HOME_IMPORTS, NEW_HOME_IMPORTS,
           "HOME: imports for the Seal-style card",
           already="import androidx.compose.material3.ElevatedCard")

# ---------------------------------------------------------------------------
# Edit 2: HomeScreen InfoCard -- full-width 16:9 thumbnail, duration badge
# on its bottom-end corner, title + channel below, Seal-style.
# ---------------------------------------------------------------------------
OLD_INFOCARD = '''@Composable
private fun InfoCard(info: VideoInfo) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier.padding(12.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            AsyncImage(
                model = info.thumbnail,
                contentDescription = null,
                modifier = Modifier
                    .width(120.dp)
                    .height(68.dp)
                    .clip(RoundedCornerShape(8.dp)),
                contentScale = ContentScale.Crop
            )
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(
                    info.title ?: "Untitled",
                    style = MaterialTheme.typography.titleSmall,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis
                )
                info.uploader?.let {
                    Text(
                        it,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
                info.duration?.let {
                    Text(
                        formatDuration(it),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }
    }
}'''

NEW_INFOCARD = '''@Composable
private fun InfoCard(info: VideoInfo) {
    ElevatedCard(
        modifier = Modifier.fillMaxWidth(),
        shape = MaterialTheme.shapes.small
    ) {
        Column {
            Box(Modifier.fillMaxWidth()) {
                AsyncImage(
                    model = info.thumbnail,
                    contentDescription = null,
                    modifier = Modifier
                        .fillMaxWidth()
                        .aspectRatio(16f / 9f, matchHeightConstraintsFirst = true)
                        .clip(MaterialTheme.shapes.small),
                    contentScale = ContentScale.Crop
                )
                info.duration?.let { seconds ->
                    Surface(
                        modifier = Modifier
                            .padding(4.dp)
                            .align(Alignment.BottomEnd),
                        color = Color.Black.copy(alpha = 0.68f),
                        shape = MaterialTheme.shapes.extraSmall
                    ) {
                        Text(
                            modifier = Modifier.padding(horizontal = 4.dp),
                            text = formatDuration(seconds),
                            style = MaterialTheme.typography.labelSmall,
                            color = Color.White
                        )
                    }
                }
            }
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(12.dp),
                horizontalAlignment = Alignment.Start
            ) {
                Text(
                    text = info.title ?: "Untitled",
                    style = MaterialTheme.typography.titleMedium,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis
                )
                info.uploader?.let {
                    Text(
                        modifier = Modifier.padding(top = 3.dp),
                        text = it,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis
                    )
                }
            }
        }
    }
}'''

apply_edit(HOME_S, OLD_INFOCARD, NEW_INFOCARD,
           "HOME: Seal-style InfoCard with duration badge",
           already="ElevatedCard(\n        modifier = Modifier.fillMaxWidth(),")

# ---------------------------------------------------------------------------
# Edit 3: SettingsScreen -- remove the About card. Idempotency marker is
# the About text itself (the replacement is an empty string, so the
# generic "new in src" check cannot be used).
# ---------------------------------------------------------------------------
ABOUT_MARKER = 'Text("About", style = MaterialTheme.typography.titleMedium)'
ABOUT_BLOCK = '''        Card(modifier = Modifier.fillMaxWidth()) {
            Column(
                modifier = Modifier.padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Text("About", style = MaterialTheme.typography.titleMedium)
                Text("FFMux 1.0.0", style = MaterialTheme.typography.bodyMedium)
                Text(
                    "A minimal video and audio downloader powered by yt-dlp. " +
                        "UI inspired by Seal, update flow inspired by YTDLnis.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
'''

src = rd(SET_S)
if ABOUT_MARKER not in src:
    edits_skipped += 1
    print("  [skip]    SETTINGS: About card removal")
else:
    target = "\n" + ABOUT_BLOCK
    n = src.count(target)
    if n != 1:
        FAILED.append("SETTINGS: About card removal (anchor count " + str(n) + ")")
        print("  [FAIL]    SETTINGS: About card removal (anchor count " + str(n) + ")")
    else:
        wr(SET_S, src.replace(target, ""))
        edits_applied += 1
        print("  [applied] SETTINGS: About card removal")

# ---------------------------------------------------------------------------
# Edit 4: AppRoot imports -- swap NavigationBar imports for the animation
# and layout imports the custom bar needs.
# ---------------------------------------------------------------------------
OLD_ROOT_IMPORTS = '''import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.ffmux.app.ui.downloads.DownloadsScreen
import com.ffmux.app.ui.home.HomeScreen
import com.ffmux.app.ui.settings.SettingsScreen'''

NEW_ROOT_IMPORTS = '''import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.keyframes
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.ffmux.app.ui.downloads.DownloadsScreen
import com.ffmux.app.ui.home.HomeScreen
import com.ffmux.app.ui.settings.SettingsScreen'''

apply_edit(ROOT_S, OLD_ROOT_IMPORTS, NEW_ROOT_IMPORTS,
           "ROOT: imports for the custom nav bar",
           already="import androidx.compose.foundation.shape.CircleShape")

# ---------------------------------------------------------------------------
# Edit 5a: AppRoot constants for the pill bar geometry.
# ---------------------------------------------------------------------------
OLD_TABS_TAIL = '''private val tabs = listOf(
    Tab("home", "Home", Icons.Filled.Home),
    Tab("downloads", "Downloads", Icons.Filled.Download),
    Tab("settings", "Settings", Icons.Filled.Settings)
)

@Composable
fun AppRoot() {'''

NEW_TABS_TAIL = '''private val tabs = listOf(
    Tab("home", "Home", Icons.Filled.Home),
    Tab("downloads", "Downloads", Icons.Filled.Download),
    Tab("settings", "Settings", Icons.Filled.Settings)
)

private val PillWidth = 64.dp
private val PillHeight = 32.dp
private val BarHeight = 80.dp
private val LabelSlotHeight = 24.dp

@Composable
fun AppRoot() {'''

apply_edit(ROOT_S, OLD_TABS_TAIL, NEW_TABS_TAIL,
           "ROOT: pill bar constants",
           already="private val PillWidth = 64.dp")

# ---------------------------------------------------------------------------
# Edit 5b: AppRoot body -- replace the stock NavigationBar block with the
# sliding-pill bar call.
# ---------------------------------------------------------------------------
OLD_ROOT_BODY = '''    Scaffold(
        bottomBar = {
            NavigationBar {
                tabs.forEach { tab ->
                    NavigationBarItem(
                        selected = currentRoute == tab.route,
                        onClick = { navController.navigateTab(tab.route) },
                        icon = { Icon(tab.icon, contentDescription = tab.label) },
                        label = { Text(tab.label) }
                    )
                }
            }
        }
    ) { padding ->'''

NEW_ROOT_BODY = '''    Scaffold(
        bottomBar = {
            SlidingPillNavBar(
                currentRoute = currentRoute,
                onTabSelected = { route -> navController.navigateTab(route) }
            )
        }
    ) { padding ->'''

apply_edit(ROOT_S, OLD_ROOT_BODY, NEW_ROOT_BODY,
           "ROOT: use SlidingPillNavBar in the scaffold",
           already="SlidingPillNavBar(")

# ---------------------------------------------------------------------------
# Edit 5c: AppRoot -- insert the SlidingPillNavBar and NavTabItem
# composables between AppRoot and the navigateTab helper.
# ---------------------------------------------------------------------------
OLD_ROOT_TAIL = '''        }
    }
}

private fun androidx.navigation.NavHostController.navigateTab(route: String) {'''

NEW_ROOT_TAIL = '''        }
    }
}

@Composable
private fun SlidingPillNavBar(
    currentRoute: String?,
    onTabSelected: (String) -> Unit
) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        color = MaterialTheme.colorScheme.surfaceContainer,
        tonalElevation = 3.dp
    ) {
        BoxWithConstraints(
            modifier = Modifier
                .fillMaxWidth()
                .navigationBarsPadding()
                .height(BarHeight)
        ) {
            val tabWidth = maxWidth / tabs.size
            val selectedIndex =
                tabs.indexOfFirst { it.route == currentRoute }.coerceAtLeast(0)

            val pillOffset by animateDpAsState(
                targetValue = tabWidth * selectedIndex + (tabWidth - PillWidth) / 2,
                animationSpec = spring(
                    dampingRatio = Spring.DampingRatioLowBouncy,
                    stiffness = Spring.StiffnessMediumLow
                ),
                label = "pillOffset"
            )

            Column(modifier = Modifier.matchParentSize()) {
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxWidth()
                ) {
                    Box(
                        modifier = Modifier
                            .align(Alignment.CenterStart)
                            .offset(x = pillOffset)
                            .size(PillWidth, PillHeight)
                            .clip(CircleShape)
                            .background(MaterialTheme.colorScheme.secondaryContainer)
                    )
                }
                Spacer(modifier = Modifier.height(LabelSlotHeight))
            }

            Row(modifier = Modifier.fillMaxWidth()) {
                tabs.forEach { tab ->
                    NavTabItem(
                        tab = tab,
                        selected = currentRoute == tab.route,
                        onClick = { onTabSelected(tab.route) }
                    )
                }
            }
        }
    }
}

@Composable
private fun RowScope.NavTabItem(
    tab: Tab,
    selected: Boolean,
    onClick: () -> Unit
) {
    val scale = remember { Animatable(1f) }
    var firstComposition by remember { mutableStateOf(true) }

    LaunchedEffect(selected) {
        if (firstComposition) {
            firstComposition = false
            return@LaunchedEffect
        }
        if (selected) {
            scale.snapTo(1f)
            scale.animateTo(
                targetValue = 1f,
                animationSpec = keyframes {
                    durationMillis = 400
                    0.75f at 150 using FastOutSlowInEasing
                }
            )
        }
    }

    Column(
        modifier = Modifier
            .weight(1f)
            .fillMaxHeight()
            .selectable(
                selected = selected,
                onClick = onClick
            ),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Box(
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth(),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = tab.icon,
                contentDescription = tab.label,
                modifier = Modifier
                    .size(26.dp)
                    .scale(scale.value),
                tint = if (selected) MaterialTheme.colorScheme.onSecondaryContainer
                else MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        Box(
            modifier = Modifier.height(LabelSlotHeight),
            contentAlignment = Alignment.Center
        ) {
            Text(
                text = tab.label,
                style = MaterialTheme.typography.labelMedium,
                color = if (selected) MaterialTheme.colorScheme.onSecondaryContainer
                else MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1
            )
        }
    }
}

private fun androidx.navigation.NavHostController.navigateTab(route: String) {'''

apply_edit(ROOT_S, OLD_ROOT_TAIL, NEW_ROOT_TAIL,
           "ROOT: sliding pill nav bar + bounce tabs",
           already="private fun SlidingPillNavBar(")

# ===========================================================================
# PATCH 2
# ===========================================================================

# ---------------------------------------------------------------------------
# Edit 6: AppRoot imports, round 2 -- tween / fadeIn / fadeOut for the
# fast NavHost crossfade, and MutableInteractionSource for turning the
# press ripple off.
# ---------------------------------------------------------------------------
OLD_ROOT_IMPORTS2 = '''import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box'''

NEW_ROOT_IMPORTS2 = '''import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box'''

apply_edit(ROOT_S, OLD_ROOT_IMPORTS2, NEW_ROOT_IMPORTS2,
           "ROOT: tween/fade + interaction imports",
           already="import androidx.compose.foundation.interaction.MutableInteractionSource")

# ---------------------------------------------------------------------------
# Edit 7: NavHost -- replace the slow default crossfade (the navigation
# library's default is a 700ms fade) with an explicit fast one.
# ---------------------------------------------------------------------------
OLD_NAVHOST = '''        NavHost(
            navController = navController,
            startDestination = "home",
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
        ) {'''

NEW_NAVHOST = '''        NavHost(
            navController = navController,
            startDestination = "home",
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
            enterTransition = { fadeIn(tween(150)) },
            exitTransition = { fadeOut(tween(100)) },
            popEnterTransition = { fadeIn(tween(150)) },
            popExitTransition = { fadeOut(tween(100)) }
        ) {'''

apply_edit(ROOT_S, OLD_NAVHOST, NEW_NAVHOST,
           "ROOT: fast NavHost crossfade (150/100ms)",
           already="enterTransition = { fadeIn(tween(150)) }")

# ---------------------------------------------------------------------------
# Edit 8: pill spring -- raise stiffness so the pill settles in ~300ms
# instead of gliding for the better part of a second.
# ---------------------------------------------------------------------------
OLD_SPRING = '''                animationSpec = spring(
                    dampingRatio = Spring.DampingRatioLowBouncy,
                    stiffness = Spring.StiffnessMediumLow
                ),'''

NEW_SPRING = '''                animationSpec = spring(
                    dampingRatio = Spring.DampingRatioLowBouncy,
                    stiffness = Spring.StiffnessMedium
                ),'''

apply_edit(ROOT_S, OLD_SPRING, NEW_SPRING,
           "ROOT: pill spring stiffness MediumLow -> Medium",
           already="Spring.StiffnessMedium\n")

# ---------------------------------------------------------------------------
# Edit 9: icon bounce -- shorten the squeeze from 400ms to 280ms.
# ---------------------------------------------------------------------------
OLD_KEYFRAMES = '''                animationSpec = keyframes {
                    durationMillis = 400
                    0.75f at 150 using FastOutSlowInEasing
                }'''

NEW_KEYFRAMES = '''                animationSpec = keyframes {
                    durationMillis = 280
                    0.78f at 100 using FastOutSlowInEasing
                }'''

apply_edit(ROOT_S, OLD_KEYFRAMES, NEW_KEYFRAMES,
           "ROOT: icon bounce 400ms -> 280ms",
           already="durationMillis = 280")

# ---------------------------------------------------------------------------
# Edit 10: remove the gray press ripple from the tab items.
# ---------------------------------------------------------------------------
OLD_SELECTABLE = '''        modifier = Modifier
            .weight(1f)
            .fillMaxHeight()
            .selectable(
                selected = selected,
                onClick = onClick
            ),'''

NEW_SELECTABLE = '''        modifier = Modifier
            .weight(1f)
            .fillMaxHeight()
            .selectable(
                selected = selected,
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
                onClick = onClick
            ),'''

apply_edit(ROOT_S, OLD_SELECTABLE, NEW_SELECTABLE,
           "ROOT: no press ripple on tabs",
           already="indication = null")

# ---------------------------------------------------------------------------
# Edit 11: HomeScreen imports, round 2 -- LocalConfiguration, FontWeight
# and sp for the screen-scaled duration badge font.
# ---------------------------------------------------------------------------
OLD_HOME_IMPORTS2 = '''import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp'''

NEW_HOME_IMPORTS2 = '''import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp'''

apply_edit(HOME_S, OLD_HOME_IMPORTS2, NEW_HOME_IMPORTS2,
           "HOME: LocalConfiguration/FontWeight/sp imports",
           already="import androidx.compose.ui.platform.LocalConfiguration")

# ---------------------------------------------------------------------------
# Edit 12: duration badge -- bigger, screen-size aware text instead of
# the fixed 11sp labelSmall.
# ---------------------------------------------------------------------------
OLD_BADGE = '''                info.duration?.let { seconds ->
                    Surface(
                        modifier = Modifier
                            .padding(4.dp)
                            .align(Alignment.BottomEnd),
                        color = Color.Black.copy(alpha = 0.68f),
                        shape = MaterialTheme.shapes.extraSmall
                    ) {
                        Text(
                            modifier = Modifier.padding(horizontal = 4.dp),
                            text = formatDuration(seconds),
                            style = MaterialTheme.typography.labelSmall,
                            color = Color.White
                        )
                    }
                }'''

NEW_BADGE = '''                info.duration?.let { seconds ->
                    val config = LocalConfiguration.current
                    val durationFontSize =
                        (config.screenWidthDp * 0.038f).coerceIn(12f, 18f).sp
                    Surface(
                        modifier = Modifier
                            .padding(6.dp)
                            .align(Alignment.BottomEnd),
                        color = Color.Black.copy(alpha = 0.68f),
                        shape = MaterialTheme.shapes.extraSmall
                    ) {
                        Text(
                            modifier = Modifier.padding(horizontal = 6.dp, vertical = 1.dp),
                            text = formatDuration(seconds),
                            fontSize = durationFontSize,
                            lineHeight = (durationFontSize.value * 1.15f).sp,
                            fontWeight = FontWeight.Medium,
                            color = Color.White
                        )
                    }
                }'''

apply_edit(HOME_S, OLD_BADGE, NEW_BADGE,
           "HOME: duration badge scales with screen (12-18sp)",
           already="config.screenWidthDp * 0.038f")

# ===========================================================================
# YOUTUBEDL-ANDROID 0.18.1 NULL-SAFETY (repo fix a99ed1b, folded in so
# that even a pre-fix tree compiles on GitHub Actions)
# ===========================================================================

OLD_ENGINE_VERSION = r'''    suspend fun currentVersion(): String = withContext(Dispatchers.IO) {
        runCatching { YoutubeDL.getInstance().version(appContext) }.getOrDefault("unknown")
    }'''

NEW_ENGINE_VERSION = r'''    suspend fun currentVersion(): String = withContext(Dispatchers.IO) {
        runCatching { YoutubeDL.getInstance().version(appContext) }.getOrNull() ?: "unknown"
    }'''

apply_edit(ENG_S, OLD_ENGINE_VERSION, NEW_ENGINE_VERSION,
           "ENGINE: null-safe currentVersion",
           already='.getOrNull() ?: "unknown"')

OLD_ENGINE_UPDATE = r'''            when (YoutubeDL.getInstance()
                .updateYoutubeDL(appContext, YoutubeDL.UpdateChannel.STABLE)) {
                YoutubeDL.UpdateStatus.DONE -> "yt-dlp has been updated."
                YoutubeDL.UpdateStatus.ALREADY_UP_TO_DATE -> "yt-dlp is already up to date."
            }'''

NEW_ENGINE_UPDATE = r'''            when (YoutubeDL.getInstance()
                .updateYoutubeDL(appContext, YoutubeDL.UpdateChannel.STABLE)) {
                YoutubeDL.UpdateStatus.DONE -> "yt-dlp has been updated."
                YoutubeDL.UpdateStatus.ALREADY_UP_TO_DATE -> "yt-dlp is already up to date."
                else -> "yt-dlp is already up to date."
            }'''

apply_edit(ENG_S, OLD_ENGINE_UPDATE, NEW_ENGINE_UPDATE,
           "ENGINE: exhaustive update() when",
           already='else -> "yt-dlp is already up to date."')

# ===========================================================================
# PATCH 3
# ===========================================================================

# ---------------------------------------------------------------------------
# Edit 14: Models -- FormatOption grows optional spec fields (container,
# fps, bitrate, size text, free-text note). Defaults keep every existing
# constructor call valid.
# ---------------------------------------------------------------------------
OLD_MODELS = r'''data class FormatOption(
    val label: String,
    val selector: String,
    val kind: FormatKind
)'''

NEW_MODELS = r'''data class FormatOption(
    val label: String,
    val selector: String,
    val kind: FormatKind,
    val ext: String? = null,
    val fps: Int? = null,
    val kbps: Int? = null,
    val size: String? = null,
    val note: String? = null
)'''

apply_edit(MOD_S, OLD_MODELS, NEW_MODELS,
           "MODELS: FormatOption spec fields",
           already="val note: String? = null")

# ---------------------------------------------------------------------------
# Edit 15: Engine -- buildFormatOptions now returns a pinned Best option
# first, then one card per video height (with container/fps/size taken
# from the best matching stream), then one card per audio container
# (with bitrate/size). Sizes come from the reported filesize, or a
# tbr x duration estimate, and video cards add the best audio stream
# because the download muxes the two.
# ---------------------------------------------------------------------------
OLD_ENGINE_FORMATS = r'''        /** Builds the quality options shown on the Home screen. */
        fun buildFormatOptions(info: VideoInfo): List<FormatOption> {
            val heights = info.formats
                .filter { !it.vcodec.isNullOrEmpty() && it.vcodec != "none" && it.height != null }
                .map { it.height!! }
                .distinct()
                .sortedDescending()

            val video = if (heights.isEmpty()) {
                listOf(FormatOption("Best available", "bestvideo+bestaudio/best", FormatKind.VIDEO))
            } else {
                heights.map { h ->
                    FormatOption(
                        label = "${h}p",
                        selector = "bestvideo[height<=$h]+bestaudio/best[height<=$h]",
                        kind = FormatKind.VIDEO
                    )
                }
            }
            return video + FormatOption("Audio only", "bestaudio[ext=m4a]/bestaudio", FormatKind.AUDIO)
        }'''

NEW_ENGINE_FORMATS = r'''        /** Builds the quality options shown on the Home screen. */
        fun buildFormatOptions(info: VideoInfo): List<FormatOption> {
            val audioFormats = info.formats.filter {
                (it.vcodec == null || it.vcodec == "none") &&
                    !it.acodec.isNullOrEmpty() && it.acodec != "none"
            }
            val bestAudio = audioFormats.maxByOrNull { it.tbr ?: 0.0 }

            val heights = info.formats
                .filter { !it.vcodec.isNullOrEmpty() && it.vcodec != "none" && it.height != null }
                .map { it.height!! }
                .distinct()
                .sortedDescending()

            val video = heights.map { h ->
                val sample = info.formats
                    .filter { !it.vcodec.isNullOrEmpty() && it.vcodec != "none" && it.height == h }
                    .maxByOrNull { it.tbr ?: 0.0 }
                val videoBytes = estimatedBytes(sample, info.duration)
                val audioBytes =
                    if (sample == null || sample.acodec.isNullOrEmpty() || sample.acodec == "none") {
                        estimatedBytes(bestAudio, info.duration)
                    } else {
                        null
                    }
                FormatOption(
                    label = "${h}p",
                    selector = "bestvideo[height<=$h]+bestaudio/best[height<=$h]",
                    kind = FormatKind.VIDEO,
                    ext = sample?.ext?.uppercase(),
                    fps = sample?.fps?.toInt(),
                    size = sizeText(addSizes(videoBytes, audioBytes))
                )
            }

            val audio = audioFormats.mapNotNull { it.ext }.distinct().sorted().map { e ->
                val sample = audioFormats.filter { it.ext == e }.maxByOrNull { it.tbr ?: 0.0 }
                FormatOption(
                    label = e.uppercase(),
                    selector = "bestaudio[ext=$e]/bestaudio",
                    kind = FormatKind.AUDIO,
                    ext = e.uppercase(),
                    kbps = sample?.tbr?.toInt(),
                    size = sizeText(estimatedBytes(sample, info.duration))
                )
            }
            val audioOptions = if (audio.isEmpty()) {
                listOf(FormatOption("Audio only", "bestaudio[ext=m4a]/bestaudio", FormatKind.AUDIO))
            } else {
                audio
            }

            val best = FormatOption(
                label = "Best",
                selector = "bestvideo*+bestaudio/best",
                kind = FormatKind.VIDEO,
                note = "Best video + audio"
            )
            return listOf(best) + video + audioOptions
        }

        /** File size in bytes: the reported value, else a tbr x duration estimate. */
        private fun estimatedBytes(format: VideoFormat?, duration: Long?): Long? {
            format ?: return null
            format.filesize?.let { return it }
            val tbr = format.tbr ?: return null
            val seconds = duration ?: return null
            return (tbr * 125.0 * seconds).toLong()
        }

        private fun addSizes(a: Long?, b: Long?): Long? =
            if (a != null && b != null) a + b else (a ?: b)

        private fun sizeText(bytes: Long?): String? {
            if (bytes == null) return null
            val mb = bytes / 1048576.0
            return when {
                mb >= 1024.0 -> String.format("%.1f GB", mb / 1024.0)
                mb >= 100.0 -> String.format("%.0f MB", mb)
                mb >= 1.0 -> String.format("%.1f MB", mb)
                else -> String.format("%.0f KB", bytes / 1024.0)
            }
        }'''

apply_edit(ENG_S, OLD_ENGINE_FORMATS, NEW_ENGINE_FORMATS,
           "ENGINE: rich format options, Best pinned first",
           already="bestvideo*+bestaudio/best")

# ---------------------------------------------------------------------------
# Edit 16: HomeViewModel -- editable title/author state + setters.
# ---------------------------------------------------------------------------
OLD_VM_VARS = r'''    var selectedFormat by mutableStateOf(-1)

    init {'''

NEW_VM_VARS = r'''    var selectedFormat by mutableStateOf(-1)
    var editableTitle by mutableStateOf("")
        private set
    var editableUploader by mutableStateOf("")
        private set

    fun updateTitle(value: String) {
        editableTitle = value
    }

    fun updateUploader(value: String) {
        editableUploader = value
    }

    init {'''

apply_edit(VM_S, OLD_VM_VARS, NEW_VM_VARS,
           "VM: editable title/uploader state",
           already="var editableTitle by mutableStateOf")

# ---------------------------------------------------------------------------
# Edit 17: HomeViewModel -- fill the fields when info arrives.
# ---------------------------------------------------------------------------
OLD_VM_FETCH = r'''                selectedFormat = 0
                state = HomeUiState.Info(info, options)'''

NEW_VM_FETCH = r'''                selectedFormat = 0
                editableTitle = info.title ?: "Untitled"
                editableUploader = info.uploader ?: ""
                state = HomeUiState.Info(info, options)'''

apply_edit(VM_S, OLD_VM_FETCH, NEW_VM_FETCH,
           "VM: fill names on fetch",
           already='editableTitle = info.title ?: "Untitled"')

# ---------------------------------------------------------------------------
# Edit 18: HomeViewModel -- the download entry carries the edited names.
# ---------------------------------------------------------------------------
OLD_VM_START = r'''            val entity = DownloadEntity(
                url = target,
                title = info.title ?: "Untitled",
                thumbnail = info.thumbnail,
                uploader = info.uploader,'''

NEW_VM_START = r'''            val entity = DownloadEntity(
                url = target,
                title = editableTitle.ifBlank { info.title ?: "Untitled" },
                thumbnail = info.thumbnail,
                uploader = editableUploader.ifBlank { info.uploader },'''

apply_edit(VM_S, OLD_VM_START, NEW_VM_START,
           "VM: use edited names for the download",
           already="title = editableTitle.ifBlank")

# ---------------------------------------------------------------------------
# Edit 19: HomeScreen imports, round 3 -- animation, border, background,
# Seal's audio/video icons, the pencil; RadioButton is no longer used.
# ---------------------------------------------------------------------------
OLD_HOME_IMPORTS3 = r'''import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ContentPaste
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text'''

NEW_HOME_IMPORTS3 = r'''import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ContentPaste
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.rounded.Audiotrack
import androidx.compose.material.icons.rounded.Videocam
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text'''

apply_edit(HOME_S, OLD_HOME_IMPORTS3, NEW_HOME_IMPORTS3,
           "HOME: format card + icon imports",
           already="import androidx.compose.material.icons.rounded.Videocam")

# ---------------------------------------------------------------------------
# Edit 20: HomeScreen imports -- FormatKind / FormatOption from the engine.
# ---------------------------------------------------------------------------
OLD_HOME_IMPORTS4 = r'''import com.ffmux.app.Graph
import com.ffmux.app.engine.VideoInfo
import com.ffmux.app.util.UrlUtils'''

NEW_HOME_IMPORTS4 = r'''import com.ffmux.app.Graph
import com.ffmux.app.engine.FormatKind
import com.ffmux.app.engine.FormatOption
import com.ffmux.app.engine.VideoInfo
import com.ffmux.app.util.UrlUtils'''

apply_edit(HOME_S, OLD_HOME_IMPORTS4, NEW_HOME_IMPORTS4,
           "HOME: engine imports",
           already="import com.ffmux.app.engine.FormatKind")

# ---------------------------------------------------------------------------
# Edit 21: HomeScreen Info state -- the radio-button list becomes a
# two-column grid of compact format cards, and InfoCard receives the
# editable fields.
# ---------------------------------------------------------------------------
OLD_HOME_INFO = r'''            is HomeUiState.Info -> {
                InfoCard(current.info)
                Text("Format", style = MaterialTheme.typography.titleMedium)
                current.options.forEachIndexed { index, option ->
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .selectable(
                                selected = index == viewModel.selectedFormat,
                                onClick = { viewModel.selectedFormat = index }
                            )
                            .padding(vertical = 2.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        RadioButton(
                            selected = index == viewModel.selectedFormat,
                            onClick = { viewModel.selectedFormat = index }
                        )
                        Text(option.label, style = MaterialTheme.typography.bodyLarge)
                    }
                }
                Button(
                    onClick = { viewModel.startDownload(onDownloadStarted) },
                    modifier = Modifier.fillMaxWidth(),
                    enabled = viewModel.selectedFormat >= 0
                ) {
                    Text("Download")
                }
            }'''

NEW_HOME_INFO = r'''            is HomeUiState.Info -> {
                InfoCard(
                    info = current.info,
                    title = viewModel.editableTitle,
                    onTitleChange = { viewModel.updateTitle(it) },
                    uploader = viewModel.editableUploader,
                    onUploaderChange = { viewModel.updateUploader(it) }
                )
                Text("Format", style = MaterialTheme.typography.titleMedium)
                current.options.chunked(2).forEachIndexed { rowIndex, rowOptions ->
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        rowOptions.forEachIndexed { colIndex, option ->
                            val index = rowIndex * 2 + colIndex
                            FormatCard(
                                option = option,
                                isBest = index == 0,
                                selected = index == viewModel.selectedFormat,
                                onClick = { viewModel.selectedFormat = index },
                                modifier = Modifier.weight(1f)
                            )
                        }
                        if (rowOptions.size == 1) {
                            Spacer(modifier = Modifier.weight(1f))
                        }
                    }
                }
                Button(
                    onClick = { viewModel.startDownload(onDownloadStarted) },
                    modifier = Modifier.fillMaxWidth(),
                    enabled = viewModel.selectedFormat >= 0
                ) {
                    Text("Download")
                }
            }'''

apply_edit(HOME_S, OLD_HOME_INFO, NEW_HOME_INFO,
           "HOME: format cards + editable InfoCard call",
           already="chunked(2)")

# ---------------------------------------------------------------------------
# Edit 22: InfoCard signature -- takes the editable fields.
# ---------------------------------------------------------------------------
OLD_INFOCARD_SIG = r'''@Composable
private fun InfoCard(info: VideoInfo) {
    ElevatedCard('''

NEW_INFOCARD_SIG = r'''@Composable
private fun InfoCard(
    info: VideoInfo,
    title: String,
    onTitleChange: (String) -> Unit,
    uploader: String,
    onUploaderChange: (String) -> Unit
) {
    ElevatedCard('''

apply_edit(HOME_S, OLD_INFOCARD_SIG, NEW_INFOCARD_SIG,
           "HOME: InfoCard signature takes editable fields",
           already="onTitleChange: (String) -> Unit")

# ---------------------------------------------------------------------------
# Edit 23: InfoCard body -- static title/uploader texts become Title and
# Author text fields (pencil icon marks the title as editable).
# ---------------------------------------------------------------------------
OLD_INFOCARD_FIELDS = r'''                Text(
                    text = info.title ?: "Untitled",
                    style = MaterialTheme.typography.titleMedium,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis
                )
                info.uploader?.let {
                    Text(
                        modifier = Modifier.padding(top = 3.dp),
                        text = it,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis
                    )
                }'''

NEW_INFOCARD_FIELDS = r'''                OutlinedTextField(
                    value = title,
                    onValueChange = onTitleChange,
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("Title") },
                    singleLine = true,
                    textStyle = MaterialTheme.typography.titleMedium,
                    shape = MaterialTheme.shapes.small,
                    trailingIcon = {
                        Icon(
                            Icons.Outlined.Edit,
                            contentDescription = null,
                            modifier = Modifier.size(16.dp),
                            tint = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                )
                OutlinedTextField(
                    value = uploader,
                    onValueChange = onUploaderChange,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = 8.dp),
                    label = { Text("Author") },
                    singleLine = true,
                    textStyle = MaterialTheme.typography.bodyMedium,
                    shape = MaterialTheme.shapes.small
                )'''

apply_edit(HOME_S, OLD_INFOCARD_FIELDS, NEW_INFOCARD_FIELDS,
           "HOME: Title/Author editable fields",
           already='label = { Text("Author") }')

# ---------------------------------------------------------------------------
# Edit 24: HomeScreen -- the compact Seal-style FormatCard and the spec
# line builder, inserted above formatDuration.
# ---------------------------------------------------------------------------
OLD_HOME_TAIL = r'''private fun formatDuration(seconds: Long): String {'''

NEW_HOME_TAIL = r'''@Composable
private fun FormatCard(
    option: FormatOption,
    isBest: Boolean,
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    val video = option.kind == FormatKind.VIDEO
    val showAudio = option.kind == FormatKind.AUDIO || isBest
    val outlineColor: Color
    val containerColor: Color
    if (video) {
        outlineColor = MaterialTheme.colorScheme.primary
        containerColor = MaterialTheme.colorScheme.primaryContainer
    } else {
        outlineColor = MaterialTheme.colorScheme.secondary
        containerColor = MaterialTheme.colorScheme.secondaryContainer
    }
    val animatedOutline by animateColorAsState(
        targetValue = if (selected) outlineColor else MaterialTheme.colorScheme.outlineVariant,
        animationSpec = tween(100), label = "formatOutline"
    )
    val animatedContainer by animateColorAsState(
        targetValue = if (selected) containerColor else MaterialTheme.colorScheme.surface,
        animationSpec = tween(100), label = "formatContainer"
    )
    val animatedTitle by animateColorAsState(
        targetValue = if (selected) outlineColor else MaterialTheme.colorScheme.onSurface,
        animationSpec = tween(100), label = "formatTitle"
    )
    Box(
        modifier = modifier
            .clip(MaterialTheme.shapes.small)
            .selectable(selected = selected, onClick = onClick)
            .border(1.dp, animatedOutline, MaterialTheme.shapes.small)
            .background(animatedContainer)
    ) {
        Column(
            modifier = Modifier.padding(start = 10.dp, top = 8.dp, end = 10.dp, bottom = 22.dp)
        ) {
            Text(
                text = option.label,
                style = MaterialTheme.typography.titleSmall,
                color = animatedTitle,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            formatSpec(option)?.let {
                Text(
                    text = it,
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
        }
        Row(
            modifier = Modifier
                .align(Alignment.BottomEnd)
                .padding(4.dp),
            horizontalArrangement = Arrangement.spacedBy(2.dp)
        ) {
            if (video) {
                Icon(
                    imageVector = Icons.Rounded.Videocam,
                    contentDescription = "Video",
                    tint = animatedOutline,
                    modifier = Modifier.size(14.dp)
                )
            }
            if (showAudio) {
                Icon(
                    imageVector = Icons.Rounded.Audiotrack,
                    contentDescription = "Audio",
                    tint = animatedOutline,
                    modifier = Modifier.size(14.dp)
                )
            }
        }
    }
}

private fun formatSpec(option: FormatOption): String? {
    option.note?.let { return it }
    val parts = mutableListOf<String>()
    option.ext?.let { parts.add(it) }
    if (option.kind == FormatKind.AUDIO) {
        option.kbps?.let { parts.add("${it} kbps") }
    } else {
        option.fps?.let { parts.add("${it} fps") }
    }
    option.size?.let { parts.add(it) }
    if (parts.isEmpty()) return null
    return parts.joinToString(" \u00B7 ")
}

private fun formatDuration(seconds: Long): String {'''

apply_edit(HOME_S, OLD_HOME_TAIL, NEW_HOME_TAIL,
           "HOME: FormatCard composable + spec builder",
           already="private fun FormatCard(")

# ---------------------------------------------------------------------------
# Edit 25: DownloadService -- the saved file is named after the (edited)
# title instead of yt-dlp's own title + [id], with the characters that
# no filesystem likes stripped out.
# ---------------------------------------------------------------------------
OLD_SVC_TEMPLATE = r'''        val tempDir = File(cacheDir, "downloads/${item.id}").apply { mkdirs() }
        val template = "${tempDir.absolutePath}/%(title).80s [%(id)s].%(ext)s"'''

NEW_SVC_TEMPLATE = r'''        val tempDir = File(cacheDir, "downloads/${item.id}").apply { mkdirs() }
        val safeTitle = item.title
            .replace(Regex("[\\/:*?\"<>|%]"), "_")
            .trim()
            .take(80)
            .ifEmpty { "Untitled" }
        val template = "${tempDir.absolutePath}/$safeTitle.%(ext)s"'''

apply_edit(SVC_S, OLD_SVC_TEMPLATE, NEW_SVC_TEMPLATE,
           "SERVICE: filename follows the edited title",
           already="val safeTitle = item.title")

# ===========================================================================
# PATCH 4
# ===========================================================================

# ---------------------------------------------------------------------------
# Edit 26: Models -- VideoFormat grows a width field so the cards can
# show the full resolution (1920x1080), like Seal does.
# ---------------------------------------------------------------------------
OLD_VF = '''    @SerialName("format_id") val formatId: String? = null,
    val ext: String? = null,
    val height: Int? = null,'''

NEW_VF = '''    @SerialName("format_id") val formatId: String? = null,
    val ext: String? = null,
    val width: Int? = null,
    val height: Int? = null,'''

apply_edit(MOD_S, OLD_VF, NEW_VF,
           "MODELS: VideoFormat width field",
           already="val width: Int? = null")

# ---------------------------------------------------------------------------
# Edit 27: Models -- FormatOption becomes a per-stream card: format id,
# width/height, byte size, has-audio flag; plus the FormatCatalog that
# keeps video and audio streams apart, with Best on top.
# ---------------------------------------------------------------------------
OLD_FO = '''data class FormatOption(
    val label: String,
    val selector: String,
    val kind: FormatKind,
    val ext: String? = null,
    val fps: Int? = null,
    val kbps: Int? = null,
    val size: String? = null,
    val note: String? = null
)'''

NEW_FO = '''data class FormatOption(
    val id: String,
    val label: String,
    val selector: String,
    val kind: FormatKind,
    val ext: String? = null,
    val width: Int? = null,
    val height: Int? = null,
    val fps: Int? = null,
    val kbps: Int? = null,
    val size: String? = null,
    val sizeBytes: Long? = null,
    val note: String? = null,
    val hasAudio: Boolean = false,
    val isBest: Boolean = false
)

data class FormatCatalog(
    val best: FormatOption,
    val video: List<FormatOption>,
    val audio: List<FormatOption>
)'''

apply_edit(MOD_S, OLD_FO, NEW_FO,
           "MODELS: per-stream FormatOption + FormatCatalog",
           already="data class FormatCatalog(")

# ---------------------------------------------------------------------------
# Edit 28: Engine -- buildFormatOptions returns the catalog: every stream
# is its own card with its real format id (so a video-only stream and an
# audio stream can be merged later), videos sorted by height, audios by
# bitrate, Best on top with an estimated merged size.
# ---------------------------------------------------------------------------
OLD_ENGINE_TAIL = r'''        /** Builds the quality options shown on the Home screen. */
        fun buildFormatOptions(info: VideoInfo): List<FormatOption> {
            val audioFormats = info.formats.filter {
                (it.vcodec == null || it.vcodec == "none") &&
                    !it.acodec.isNullOrEmpty() && it.acodec != "none"
            }
            val bestAudio = audioFormats.maxByOrNull { it.tbr ?: 0.0 }

            val heights = info.formats
                .filter { !it.vcodec.isNullOrEmpty() && it.vcodec != "none" && it.height != null }
                .map { it.height!! }
                .distinct()
                .sortedDescending()

            val video = heights.map { h ->
                val sample = info.formats
                    .filter { !it.vcodec.isNullOrEmpty() && it.vcodec != "none" && it.height == h }
                    .maxByOrNull { it.tbr ?: 0.0 }
                val videoBytes = estimatedBytes(sample, info.duration)
                val audioBytes =
                    if (sample == null || sample.acodec.isNullOrEmpty() || sample.acodec == "none") {
                        estimatedBytes(bestAudio, info.duration)
                    } else {
                        null
                    }
                FormatOption(
                    label = "${h}p",
                    selector = "bestvideo[height<=$h]+bestaudio/best[height<=$h]",
                    kind = FormatKind.VIDEO,
                    ext = sample?.ext?.uppercase(),
                    fps = sample?.fps?.toInt(),
                    size = sizeText(addSizes(videoBytes, audioBytes))
                )
            }

            val audio = audioFormats.mapNotNull { it.ext }.distinct().sorted().map { e ->
                val sample = audioFormats.filter { it.ext == e }.maxByOrNull { it.tbr ?: 0.0 }
                FormatOption(
                    label = e.uppercase(),
                    selector = "bestaudio[ext=$e]/bestaudio",
                    kind = FormatKind.AUDIO,
                    ext = e.uppercase(),
                    kbps = sample?.tbr?.toInt(),
                    size = sizeText(estimatedBytes(sample, info.duration))
                )
            }
            val audioOptions = if (audio.isEmpty()) {
                listOf(FormatOption("Audio only", "bestaudio[ext=m4a]/bestaudio", FormatKind.AUDIO))
            } else {
                audio
            }

            val best = FormatOption(
                label = "Best",
                selector = "bestvideo*+bestaudio/best",
                kind = FormatKind.VIDEO,
                note = "Best video + audio"
            )
            return listOf(best) + video + audioOptions
        }

        /** File size in bytes: the reported value, else a tbr x duration estimate. */
        private fun estimatedBytes(format: VideoFormat?, duration: Long?): Long? {
            format ?: return null
            format.filesize?.let { return it }
            val tbr = format.tbr ?: return null
            val seconds = duration ?: return null
            return (tbr * 125.0 * seconds).toLong()
        }

        private fun addSizes(a: Long?, b: Long?): Long? =
            if (a != null && b != null) a + b else (a ?: b)

        private fun sizeText(bytes: Long?): String? {
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
}'''

NEW_ENGINE_TAIL = r'''        /** Builds the format catalog shown on the Home screen: every
         * stream as its own card, videos and audios listed apart. */
        fun buildFormatOptions(info: VideoInfo): FormatCatalog {
            val duration = info.duration
            val audioFormats = info.formats.filter {
                (it.vcodec == null || it.vcodec == "none") &&
                    !it.acodec.isNullOrEmpty() && it.acodec != "none"
            }.distinctBy { it.formatId }
            val videoFormats = info.formats.filter {
                !it.vcodec.isNullOrEmpty() && it.vcodec != "none"
            }.distinctBy { it.formatId }

            val audio = audioFormats
                .sortedWith(compareByDescending { it.tbr ?: 0.0 })
                .map { f ->
                    val bytes = estimatedBytes(f, duration)
                    FormatOption(
                        id = f.formatId ?: "bestaudio",
                        label = f.tbr?.toInt()?.let { "$it kbps" }
                            ?: f.ext?.uppercase() ?: "Audio",
                        selector = f.formatId ?: "bestaudio",
                        kind = FormatKind.AUDIO,
                        ext = f.ext?.uppercase(),
                        kbps = f.tbr?.toInt(),
                        size = sizeText(bytes, estimated = f.filesize == null),
                        sizeBytes = bytes
                    )
                }
            val audioOptions = if (audio.isEmpty()) {
                listOf(
                    FormatOption(
                        id = "bestaudio",
                        label = "Audio only",
                        selector = "bestaudio/best",
                        kind = FormatKind.AUDIO
                    )
                )
            } else {
                audio
            }

            val video = videoFormats
                .sortedWith(
                    compareByDescending<VideoFormat> { it.height ?: 0 }
                        .thenByDescending { it.tbr ?: 0.0 }
                )
                .map { f ->
                    val bytes = estimatedBytes(f, duration)
                    FormatOption(
                        id = f.formatId ?: "bestvideo",
                        label = f.height?.let { "${it}p" }
                            ?: f.ext?.uppercase() ?: "Video",
                        selector = f.formatId ?: "bestvideo",
                        kind = FormatKind.VIDEO,
                        ext = f.ext?.uppercase(),
                        width = f.width,
                        height = f.height,
                        fps = f.fps?.toInt(),
                        kbps = f.tbr?.toInt(),
                        size = sizeText(bytes, estimated = f.filesize == null),
                        sizeBytes = bytes,
                        hasAudio = !f.acodec.isNullOrEmpty() && f.acodec != "none"
                    )
                }

            val bestVideoOnly = videoFormats
                .filter { it.acodec.isNullOrEmpty() || it.acodec == "none" }
                .maxWithOrNull(compareBy({ it.height ?: 0 }, { it.tbr ?: 0.0 }))
            val bestAudioBytes =
                audioFormats.maxByOrNull { it.tbr ?: 0.0 }?.let { estimatedBytes(it, duration) }
            val bestBytes = addSizes(
                bestVideoOnly?.let { estimatedBytes(it, duration) },
                bestAudioBytes
            )
            val best = FormatOption(
                id = "best",
                label = "Best",
                selector = "bestvideo*+bestaudio/best",
                kind = FormatKind.VIDEO,
                note = "Best video + best audio, merged",
                size = sizeText(bestBytes, estimated = true),
                sizeBytes = bestBytes,
                hasAudio = true,
                isBest = true
            )
            return FormatCatalog(best = best, video = video, audio = audioOptions)
        }

        /** File size in bytes: the reported value, else a tbr x duration estimate. */
        private fun estimatedBytes(format: VideoFormat?, duration: Long?): Long? {
            format ?: return null
            format.filesize?.let { return it }
            val tbr = format.tbr ?: return null
            val seconds = duration ?: return null
            return (tbr * 125.0 * seconds).toLong()
        }

        private fun addSizes(a: Long?, b: Long?): Long? =
            if (a != null && b != null) a + b else (a ?: b)

        private fun sizeText(bytes: Long?, estimated: Boolean): String? {
            if (bytes == null) return null
            val mb = bytes / 1048576.0
            val text = when {
                mb >= 1024.0 -> String.format("%.1f GB", mb / 1024.0)
                mb >= 100.0 -> String.format("%.0f MB", mb)
                mb >= 1.0 -> String.format("%.1f MB", mb)
                else -> String.format("%.0f KB", bytes / 1024.0)
            }
            return if (estimated) "\u2248 $text" else text
        }
    }
}'''

apply_edit(ENG_S, OLD_ENGINE_TAIL, NEW_ENGINE_TAIL,
           "ENGINE: per-stream catalog, video and audio apart",
           already="fun buildFormatOptions(info: VideoInfo): FormatCatalog")

# ---------------------------------------------------------------------------
# Edit 29: HomeViewModel imports -- FormatCatalog comes in.
# ---------------------------------------------------------------------------
apply_edit(VM_S,
           "import com.ffmux.app.engine.FormatOption",
           "import com.ffmux.app.engine.FormatCatalog\nimport com.ffmux.app.engine.FormatOption",
           "VM: import FormatCatalog",
           already="import com.ffmux.app.engine.FormatCatalog")

# ---------------------------------------------------------------------------
# Edit 30: HomeViewModel -- the Info state carries the catalog instead of
# the flat option list.
# ---------------------------------------------------------------------------
apply_edit(VM_S,
           "    data class Info(val info: VideoInfo, val options: List<FormatOption>) : HomeUiState",
           "    data class Info(val info: VideoInfo, val catalog: FormatCatalog) : HomeUiState",
           "VM: Info state carries the FormatCatalog")

# ---------------------------------------------------------------------------
# Edit 31: HomeViewModel -- one selection per side (video / audio) instead
# of a single list index. Null on both sides means "Best".
# ---------------------------------------------------------------------------
apply_edit(VM_S,
           "    var selectedFormat by mutableStateOf(-1)",
           "    var selectedVideoId by mutableStateOf<String?>(null)\n" +
           "    var selectedAudioId by mutableStateOf<String?>(null)",
           "VM: video/audio selection state",
           already="var selectedVideoId by mutableStateOf")

# ---------------------------------------------------------------------------
# Edit 32: HomeViewModel -- fetch fills the catalog and resets both
# selections (back to Best).
# ---------------------------------------------------------------------------
OLD_VM_FETCH = '''                val options = YtDlpEngine.buildFormatOptions(info)
                if (options.isEmpty()) {
                    state = HomeUiState.Error("No downloadable formats found.")
                    return@launch
                }
                selectedFormat = 0
                editableTitle = info.title ?: "Untitled"
                editableUploader = info.uploader ?: ""
                state = HomeUiState.Info(info, options)'''

NEW_VM_FETCH = '''                val catalog = YtDlpEngine.buildFormatOptions(info)
                if (catalog.video.isEmpty() && catalog.audio.isEmpty()) {
                    state = HomeUiState.Error("No downloadable formats found.")
                    return@launch
                }
                selectedVideoId = null
                selectedAudioId = null
                editableTitle = info.title ?: "Untitled"
                editableUploader = info.uploader ?: ""
                state = HomeUiState.Info(info, catalog)'''

apply_edit(VM_S, OLD_VM_FETCH, NEW_VM_FETCH,
           "VM: fetch builds the catalog and resets the selection",
           already="val catalog = YtDlpEngine.buildFormatOptions(info)")

# ---------------------------------------------------------------------------
# Edit 33: HomeViewModel -- card toggles and the merge resolution: a
# video-only stream plus an audio stream become "id+id" (merged by
# ffmpeg), progressive streams download as they are, an audio card
# alone downloads that audio, nothing picked means Best.
# ---------------------------------------------------------------------------
OLD_VM_DL = '''    fun startDownload(onQueued: () -> Unit) {
        val current = state as? HomeUiState.Info ?: return
        if (selectedFormat !in current.options.indices) return
        val option = current.options[selectedFormat]
        val info = current.info'''

NEW_VM_DL = '''    fun toggleVideo(option: FormatOption) {
        selectedVideoId = if (selectedVideoId == option.id) null else option.id
    }

    fun toggleAudio(option: FormatOption) {
        selectedAudioId = if (selectedAudioId == option.id) null else option.id
    }

    fun selectBest() {
        selectedVideoId = null
        selectedAudioId = null
    }

    /** The yt-dlp format selector for the current card selection. */
    fun resolveSelector(catalog: FormatCatalog): String {
        val video = catalog.video.firstOrNull { it.id == selectedVideoId }
        val audio = catalog.audio.firstOrNull { it.id == selectedAudioId }
        return when {
            video == null && audio == null -> catalog.best.selector
            video == null -> audio!!.selector
            video.hasAudio -> video.selector
            else -> video.selector + "+" + (audio?.selector ?: "bestaudio/best")
        }
    }

    /** Short label of the current selection, stored with the download. */
    fun resolveLabel(catalog: FormatCatalog): String {
        val video = catalog.video.firstOrNull { it.id == selectedVideoId }
        val audio = catalog.audio.firstOrNull { it.id == selectedAudioId }
        return when {
            video == null && audio == null -> "Best"
            video == null -> "Audio " + (audio?.label ?: "")
            video.hasAudio -> video.label + " (" + video.id + ")"
            else -> video.label + " (" + video.id + "+" +
                (audio?.id ?: "best audio") + ")"
        }
    }

    /** Estimated size of the file the current selection produces. */
    fun resolveSizeBytes(catalog: FormatCatalog): Long? {
        val video = catalog.video.firstOrNull { it.id == selectedVideoId }
        val audio = catalog.audio.firstOrNull { it.id == selectedAudioId }
        val fallbackAudioBytes = catalog.audio.firstOrNull()?.sizeBytes
        return when {
            video == null && audio == null -> catalog.best.sizeBytes
            video == null -> audio?.sizeBytes
            video.hasAudio -> video.sizeBytes
            else -> sumBytes(video.sizeBytes, audio?.sizeBytes ?: fallbackAudioBytes)
        }
    }

    private fun sumBytes(a: Long?, b: Long?): Long? =
        if (a != null && b != null) a + b else (a ?: b)

    fun startDownload(onQueued: () -> Unit) {
        val current = state as? HomeUiState.Info ?: return
        val selector = resolveSelector(current.catalog)
        val label = resolveLabel(current.catalog)
        val info = current.info'''

apply_edit(VM_S, OLD_VM_DL, NEW_VM_DL,
           "VM: card toggles + selector/label/size resolution",
           already="fun resolveSelector(catalog: FormatCatalog): String")

# ---------------------------------------------------------------------------
# Edit 34: HomeViewModel -- the download entry stores the resolved
# selector and label.
# ---------------------------------------------------------------------------
apply_edit(VM_S,
           "                formatSelector = option.selector,\n" +
           "                formatLabel = option.label,",
           "                formatSelector = selector,\n" +
           "                formatLabel = label,",
           "VM: download entry uses the resolved selector",
           already="formatSelector = selector,")

# ---------------------------------------------------------------------------
# Edit 35: HomeViewModel -- reset both selections after queueing.
# Custom skip (not apply_edit): patch 5 later rewrites these exact reset
# lines away, so the skip test has to accept both the patch-4 shape
# (the two reset lines) and the patch-5 shape (the "Patch 5:" comment).
# ---------------------------------------------------------------------------
src = rd(VM_S)
if "selectedFormat = -1" in src:
    if src.count("selectedFormat = -1") != 1:
        FAILED.append("VM: reset both selections (anchor ambiguous)")
        print("  [FAIL]    VM: reset both selections (anchor ambiguous)")
    else:
        wr(VM_S, src.replace(
            "            state = HomeUiState.Idle\n" +
            "            url = \"\"\n" +
            "            selectedFormat = -1",
            "            state = HomeUiState.Idle\n" +
            "            url = \"\"\n" +
            "            selectedVideoId = null\n" +
            "            selectedAudioId = null"))
        edits_applied += 1
        print("  [applied] VM: reset both selections after queueing")
elif ("selectedVideoId = null\n            selectedAudioId = null" in src) or \
     ("Patch 5: the link, the info card and the format selection" in src):
    edits_skipped += 1
    print("  [skip]    VM: reset both selections after queueing")
else:
    FAILED.append("VM: reset both selections after queueing (anchor missing)")
    print("  [FAIL]    VM: reset both selections after queueing (anchor missing)")

# ---------------------------------------------------------------------------
# Edit 36: HomeScreen imports -- the download icon for the pinned button.
# ---------------------------------------------------------------------------
apply_edit(HOME_S,
           "import androidx.compose.material.icons.filled.ContentPaste",
           "import androidx.compose.material.icons.filled.ContentPaste\n" +
           "import androidx.compose.material.icons.filled.Download",
           "HOME: import Download icon",
           already="import androidx.compose.material.icons.filled.Download")

# ---------------------------------------------------------------------------
# Edit 37: HomeScreen root -- the scrolling column gets weight(1f) inside
# a fixed outer column, so the download button can be pinned below it.
# ---------------------------------------------------------------------------
OLD_HOME_ROOT = '''    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text("Download", style = MaterialTheme.typography.headlineMedium)'''

NEW_HOME_ROOT = '''    Column(modifier = Modifier.fillMaxSize().padding(16.dp)) {
        Column(
            modifier = Modifier
                .weight(1f)
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
        Text("Download", style = MaterialTheme.typography.headlineMedium)'''

apply_edit(HOME_S, OLD_HOME_ROOT, NEW_HOME_ROOT,
           "HOME: fixed root column, scrollable inner column",
           already=".weight(1f)\n                .verticalScroll(rememberScrollState())")

# ---------------------------------------------------------------------------
# Edit 38: HomeScreen -- the format area becomes Seal-style split
# sections: the full-width Best card, then Video cards, then Audio
# cards, two per row. The in-scroll download button is removed (it
# moves to the pinned spot in Edit 39).
# ---------------------------------------------------------------------------
OLD_HOME_SECTION = '''                Text("Format", style = MaterialTheme.typography.titleMedium)
                current.options.chunked(2).forEachIndexed { rowIndex, rowOptions ->
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        rowOptions.forEachIndexed { colIndex, option ->
                            val index = rowIndex * 2 + colIndex
                            FormatCard(
                                option = option,
                                isBest = index == 0,
                                selected = index == viewModel.selectedFormat,
                                onClick = { viewModel.selectedFormat = index },
                                modifier = Modifier.weight(1f)
                            )
                        }
                        if (rowOptions.size == 1) {
                            Spacer(modifier = Modifier.weight(1f))
                        }
                    }
                }
                Button(
                    onClick = { viewModel.startDownload(onDownloadStarted) },
                    modifier = Modifier.fillMaxWidth(),
                    enabled = viewModel.selectedFormat >= 0
                ) {
                    Text("Download")
                }'''

NEW_HOME_SECTION = '''                FormatCard(
                    option = current.catalog.best,
                    selected = viewModel.selectedVideoId == null &&
                        viewModel.selectedAudioId == null,
                    onClick = { viewModel.selectBest() },
                    modifier = Modifier.fillMaxWidth()
                )
                Text("Video", style = MaterialTheme.typography.titleSmall)
                if (current.catalog.video.isEmpty()) {
                    Text(
                        "No separate video streams",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                current.catalog.video.chunked(2).forEach { rowOptions ->
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        rowOptions.forEach { option ->
                            FormatCard(
                                option = option,
                                selected = viewModel.selectedVideoId == option.id,
                                onClick = { viewModel.toggleVideo(option) },
                                modifier = Modifier.weight(1f)
                            )
                        }
                        if (rowOptions.size == 1) {
                            Spacer(modifier = Modifier.weight(1f))
                        }
                    }
                }
                Text("Audio", style = MaterialTheme.typography.titleSmall)
                if (current.catalog.audio.isEmpty()) {
                    Text(
                        "No separate audio streams",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                current.catalog.audio.chunked(2).forEach { rowOptions ->
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        rowOptions.forEach { option ->
                            FormatCard(
                                option = option,
                                selected = viewModel.selectedAudioId == option.id,
                                onClick = { viewModel.toggleAudio(option) },
                                modifier = Modifier.weight(1f)
                            )
                        }
                        if (rowOptions.size == 1) {
                            Spacer(modifier = Modifier.weight(1f))
                        }
                    }
                }'''

apply_edit(HOME_S, OLD_HOME_SECTION, NEW_HOME_SECTION,
           "HOME: split Video / Audio card sections + Best on top",
           already='Text("Video", style = MaterialTheme.typography.titleSmall)')

# ---------------------------------------------------------------------------
# Edit 39: HomeScreen -- the download button is pinned below the
# scrolling area (it never scrolls away) and shows the estimated size
# of the file the current selection produces.
# ---------------------------------------------------------------------------
OLD_HOME_END = '''            else -> {}
        }
        Spacer(Modifier.height(8.dp))
    }
}'''

NEW_HOME_END = r'''            else -> {}
        }
        Spacer(Modifier.height(8.dp))
        }
        val currentInfo = viewModel.state as? HomeUiState.Info
        if (currentInfo != null) {
            val bytes = viewModel.resolveSizeBytes(currentInfo.catalog)
            val audioOnly =
                viewModel.selectedVideoId == null && viewModel.selectedAudioId != null
            Button(
                onClick = { viewModel.startDownload(onDownloadStarted) },
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 12.dp)
                    .height(52.dp)
            ) {
                Icon(
                    Icons.Filled.Download,
                    contentDescription = null,
                    modifier = Modifier.size(18.dp)
                )
                Spacer(Modifier.width(8.dp))
                Text(
                    if (bytes != null) {
                        (if (audioOnly) "Download audio" else "Download") +
                            " \u00B7 \u2248 " + formatSize(bytes)
                    } else {
                        if (audioOnly) "Download audio" else "Download"
                    }
                )
            }
        }
    }
}'''

apply_edit(HOME_S, OLD_HOME_END, NEW_HOME_END,
           "HOME: pinned download button with the estimated size",
           already="val currentInfo = viewModel.state as? HomeUiState.Info")

# ---------------------------------------------------------------------------
# Edit 40: HomeScreen -- the card shows the Seal marks beside the title
# and two spec lines: resolution + fps + container, then format id +
# bitrate + size.
# ---------------------------------------------------------------------------
OLD_HOME_CARD = r'''@Composable
private fun FormatCard(
    option: FormatOption,
    isBest: Boolean,
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    val video = option.kind == FormatKind.VIDEO
    val showAudio = option.kind == FormatKind.AUDIO || isBest
    val outlineColor: Color
    val containerColor: Color
    if (video) {
        outlineColor = MaterialTheme.colorScheme.primary
        containerColor = MaterialTheme.colorScheme.primaryContainer
    } else {
        outlineColor = MaterialTheme.colorScheme.secondary
        containerColor = MaterialTheme.colorScheme.secondaryContainer
    }
    val animatedOutline by animateColorAsState(
        targetValue = if (selected) outlineColor else MaterialTheme.colorScheme.outlineVariant,
        animationSpec = tween(100), label = "formatOutline"
    )
    val animatedContainer by animateColorAsState(
        targetValue = if (selected) containerColor else MaterialTheme.colorScheme.surface,
        animationSpec = tween(100), label = "formatContainer"
    )
    val animatedTitle by animateColorAsState(
        targetValue = if (selected) outlineColor else MaterialTheme.colorScheme.onSurface,
        animationSpec = tween(100), label = "formatTitle"
    )
    Box(
        modifier = modifier
            .clip(MaterialTheme.shapes.small)
            .selectable(selected = selected, onClick = onClick)
            .border(1.dp, animatedOutline, MaterialTheme.shapes.small)
            .background(animatedContainer)
    ) {
        Column(
            modifier = Modifier.padding(start = 10.dp, top = 8.dp, end = 10.dp, bottom = 22.dp)
        ) {
            Text(
                text = option.label,
                style = MaterialTheme.typography.titleSmall,
                color = animatedTitle,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            formatSpec(option)?.let {
                Text(
                    text = it,
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
        }
        Row(
            modifier = Modifier
                .align(Alignment.BottomEnd)
                .padding(4.dp),
            horizontalArrangement = Arrangement.spacedBy(2.dp)
        ) {
            if (video) {
                Icon(
                    imageVector = Icons.Rounded.Videocam,
                    contentDescription = "Video",
                    tint = animatedOutline,
                    modifier = Modifier.size(14.dp)
                )
            }
            if (showAudio) {
                Icon(
                    imageVector = Icons.Rounded.Audiotrack,
                    contentDescription = "Audio",
                    tint = animatedOutline,
                    modifier = Modifier.size(14.dp)
                )
            }
        }
    }
}

private fun formatSpec(option: FormatOption): String? {
    option.note?.let { return it }
    val parts = mutableListOf<String>()
    option.ext?.let { parts.add(it) }
    if (option.kind == FormatKind.AUDIO) {
        option.kbps?.let { parts.add("${it} kbps") }
    } else {
        option.fps?.let { parts.add("${it} fps") }
    }
    option.size?.let { parts.add(it) }
    if (parts.isEmpty()) return null
    return parts.joinToString(" \u00B7 ")
}'''

NEW_HOME_CARD = r'''@Composable
private fun FormatCard(
    option: FormatOption,
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    val video = option.kind == FormatKind.VIDEO
    val showAudio = option.kind == FormatKind.AUDIO || option.hasAudio
    val outlineColor: Color
    val containerColor: Color
    if (video) {
        outlineColor = MaterialTheme.colorScheme.primary
        containerColor = MaterialTheme.colorScheme.primaryContainer
    } else {
        outlineColor = MaterialTheme.colorScheme.secondary
        containerColor = MaterialTheme.colorScheme.secondaryContainer
    }
    val animatedOutline by animateColorAsState(
        targetValue = if (selected) outlineColor else MaterialTheme.colorScheme.outlineVariant,
        animationSpec = tween(100), label = "formatOutline"
    )
    val animatedContainer by animateColorAsState(
        targetValue = if (selected) containerColor else MaterialTheme.colorScheme.surface,
        animationSpec = tween(100), label = "formatContainer"
    )
    val animatedTitle by animateColorAsState(
        targetValue = if (selected) outlineColor else MaterialTheme.colorScheme.onSurface,
        animationSpec = tween(100), label = "formatTitle"
    )
    Box(
        modifier = modifier
            .clip(MaterialTheme.shapes.small)
            .selectable(selected = selected, onClick = onClick)
            .border(1.dp, animatedOutline, MaterialTheme.shapes.small)
            .background(animatedContainer)
    ) {
        Column(
            modifier = Modifier.padding(start = 10.dp, top = 8.dp, end = 10.dp, bottom = 8.dp)
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(2.dp)
            ) {
                Text(
                    text = option.label,
                    style = MaterialTheme.typography.titleSmall,
                    color = animatedTitle,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f)
                )
                if (video) {
                    Icon(
                        imageVector = Icons.Rounded.Videocam,
                        contentDescription = "Video",
                        tint = animatedOutline,
                        modifier = Modifier.size(14.dp)
                    )
                }
                if (showAudio) {
                    Icon(
                        imageVector = Icons.Rounded.Audiotrack,
                        contentDescription = "Audio",
                        tint = animatedOutline,
                        modifier = Modifier.size(14.dp)
                    )
                }
            }
            formatSpecLine1(option)?.let {
                Text(
                    text = it,
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
            formatSpecLine2(option)?.let {
                Text(
                    text = it,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
        }
    }
}

private fun formatSpecLine1(option: FormatOption): String? {
    if (option.isBest) return option.note
    val parts = mutableListOf<String>()
    if (option.kind == FormatKind.VIDEO) {
        val w = option.width
        val h = option.height
        if (w != null && h != null) {
            parts.add("$w\u00D7$h")
        } else {
            h?.let { parts.add("${it}p") }
        }
        option.fps?.let { parts.add("${it} fps") }
    }
    option.ext?.let { parts.add(it) }
    if (parts.isEmpty()) return null
    return parts.joinToString(" \u00B7 ")
}

private fun formatSpecLine2(option: FormatOption): String? {
    val parts = mutableListOf<String>()
    if (!option.isBest) {
        parts.add("ID " + option.id)
    }
    if (option.kind == FormatKind.VIDEO) {
        option.kbps?.let { kbps ->
            parts.add(
                if (kbps >= 1000) String.format("%.1f Mbps", kbps / 1000.0)
                else "$kbps kbps"
            )
        }
    }
    option.size?.let { parts.add(it) }
    if (parts.isEmpty()) return null
    return parts.joinToString(" \u00B7 ")
}'''

apply_edit(HOME_S, OLD_HOME_CARD, NEW_HOME_CARD,
           "HOME: card marks beside the title + two spec lines",
           already="private fun formatSpecLine1(option: FormatOption): String? {")

# ---------------------------------------------------------------------------
# Edit 41: HomeScreen -- byte formatter for the size on the button.
# ---------------------------------------------------------------------------
apply_edit(HOME_S,
           "private fun formatDuration(seconds: Long): String {",
           "private fun formatSize(bytes: Long): String {\n" +
           "    val mb = bytes / 1048576.0\n" +
           "    return when {\n" +
           "        mb >= 1024.0 -> String.format(\"%.1f GB\", mb / 1024.0)\n" +
           "        mb >= 100.0 -> String.format(\"%.0f MB\", mb)\n" +
           "        mb >= 1.0 -> String.format(\"%.1f MB\", mb)\n" +
           "        else -> String.format(\"%.0f KB\", bytes / 1024.0)\n" +
           "    }\n" +
           "}\n" +
           "\n" +
           "private fun formatDuration(seconds: Long): String {",
           "HOME: formatSize helper",
           already="private fun formatSize(bytes: Long): String {")

# ===========================================================================
# PATCH 5
# ===========================================================================

# ---------------------------------------------------------------------------
# Edit 42: Entity -- downloaded / total bytes and the terminal log column.
# ---------------------------------------------------------------------------
apply_edit(ENT_S,
    '''    val savedUri: String? = null,
    val error: String? = null,
    val createdAt: Long = 0L''',
    '''    val savedUri: String? = null,
    val error: String? = null,
    val downloadedBytes: Long? = null,
    val totalBytes: Long? = null,
    val log: String? = null,
    val createdAt: Long = 0L''',
    "ENTITY: bytes + log columns",
    already="val downloadedBytes: Long? = null")

# ---------------------------------------------------------------------------
# Edit 43: Database -- schema v2 with a real 1->2 migration, so an
# existing download history survives the update.
# ---------------------------------------------------------------------------
NEW_ADB = '''package com.ffmux.app.data.db

import androidx.room.Database
import androidx.room.RoomDatabase
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase

@Database(entities = [DownloadEntity::class], version = 2, exportSchema = false)
abstract class AppDatabase : RoomDatabase() {
    abstract fun downloadDao(): DownloadDao

    companion object {
        /** v2 adds the byte counters and the terminal log column. */
        val MIGRATION_1_2 = object : Migration(1, 2) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE downloads ADD COLUMN downloadedBytes INTEGER")
                db.execSQL("ALTER TABLE downloads ADD COLUMN totalBytes INTEGER")
                db.execSQL("ALTER TABLE downloads ADD COLUMN log TEXT")
            }
        }
    }
}
'''
src = rd(ADB_S)
if "MIGRATION_1_2" in src:
    edits_skipped += 1
    print("  [skip]    DB: schema v2 with migration")
elif "abstract fun downloadDao(): DownloadDao" not in src:
    FAILED.append("DB: schema v2 (unexpected base content)")
    print("  [FAIL]    DB: schema v2 (unexpected base content)")
else:
    wr(ADB_S, NEW_ADB)
    edits_applied += 1
    print("  [applied] DB: schema v2 with migration")

# ---------------------------------------------------------------------------
# Edit 44: Graph -- the Room builder installs the migration.
# ---------------------------------------------------------------------------
apply_edit(GR_S,
    '        db = Room.databaseBuilder(app, AppDatabase::class.java, "ffmux.db").build()',
    '''        db = Room.databaseBuilder(app, AppDatabase::class.java, "ffmux.db")
            .addMigrations(AppDatabase.MIGRATION_1_2)
            .build()''',
    "GRAPH: Room migration installed",
    already=".addMigrations(AppDatabase.MIGRATION_1_2)")

# ---------------------------------------------------------------------------
# Edit 45: Dao -- progress writes carry the byte counters and the log;
# requeue() puts a failed/canceled download back into the queue;
# resetActive() also clears the stale bytes of a killed process.
# ---------------------------------------------------------------------------
NEW_DAO = '''package com.ffmux.app.data.db

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.Query
import androidx.room.Transaction
import kotlinx.coroutines.flow.Flow

@Dao
interface DownloadDao {

    @Insert
    suspend fun insert(item: DownloadEntity): Long

    @Query("SELECT * FROM downloads ORDER BY id DESC")
    fun observeAll(): Flow<List<DownloadEntity>>

    @Query("SELECT * FROM downloads WHERE status = 'QUEUED' ORDER BY id LIMIT 1")
    suspend fun nextQueued(): DownloadEntity?

    @Query("UPDATE downloads SET status = 'RUNNING' WHERE id = :id AND status = 'QUEUED'")
    suspend fun markRunningIfQueued(id: Long): Int

    /** Atomically claims the next queued item so a late cancel cannot double-run it. */
    @Transaction
    suspend fun claimNext(): DownloadEntity? {
        val item = nextQueued() ?: return null
        return if (markRunningIfQueued(item.id) > 0) item else null
    }

    @Query("UPDATE downloads SET status = 'QUEUED', progress = 0, downloadedBytes = NULL, totalBytes = NULL WHERE status IN ('RUNNING', 'SAVING')")
    suspend fun resetActive()

    @Query("UPDATE downloads SET status = :status, progress = :progress, etaSec = :eta, downloadedBytes = :downloaded, totalBytes = :total, log = :log WHERE id = :id")
    suspend fun updateProgress(
        id: Long,
        status: String,
        progress: Float,
        eta: Long?,
        downloaded: Long?,
        total: Long?,
        log: String
    )

    @Query("UPDATE downloads SET log = :log WHERE id = :id")
    suspend fun updateLog(id: Long, log: String)

    @Query("UPDATE downloads SET status = :status WHERE id = :id")
    suspend fun setStatus(id: Long, status: String)

    @Query("UPDATE downloads SET status = 'CANCELED' WHERE id = :id AND status = 'QUEUED'")
    suspend fun cancelQueued(id: Long)

    @Query("UPDATE downloads SET status = :status, error = :error WHERE id = :id")
    suspend fun finishWithError(id: Long, status: String, error: String?)

    @Query("UPDATE downloads SET status = 'COMPLETED', progress = 100, etaSec = NULL, savedUri = :uri WHERE id = :id")
    suspend fun finish(id: Long, uri: String?)

    /** Puts a failed or canceled download back into the queue (retry). */
    @Query("UPDATE downloads SET status = 'QUEUED', progress = 0, etaSec = NULL, error = NULL, downloadedBytes = NULL, totalBytes = NULL, log = NULL WHERE id = :id AND status IN ('FAILED', 'CANCELED')")
    suspend fun requeue(id: Long): Int

    @Query("DELETE FROM downloads WHERE id = :id")
    suspend fun delete(id: Long)
}
'''
src = rd(DAO_S)
if "suspend fun requeue" in src:
    edits_skipped += 1
    print("  [skip]    DAO: progress bytes + log, requeue")
elif "claimNext" not in src or "resetActive" not in src:
    FAILED.append("DAO: rewrite (unexpected base content)")
    print("  [FAIL]    DAO: rewrite (unexpected base content)")
else:
    wr(DAO_S, NEW_DAO)
    edits_applied += 1
    print("  [applied] DAO: progress bytes + log, requeue")

# ---------------------------------------------------------------------------
# Edit 46: Engine -- retry connection resets: 10 tries per file and per
# fragment, 30s socket timeout (fixes "[errno 104] connection reset by
# peer").
# ---------------------------------------------------------------------------
apply_edit(ENG_S,
    '''        val request = YoutubeDLRequest(url).apply {
            addOption("--no-playlist")
            addOption("-f", selector)
            addOption("-o", outputTemplate)
            addOption("--no-mtime")
        }''',
    '''        val request = YoutubeDLRequest(url).apply {
            addOption("--no-playlist")
            addOption("-f", selector)
            addOption("-o", outputTemplate)
            addOption("--no-mtime")
            // YouTube likes to reset long transfers (errno 104):
            // retry every file and every fragment before giving up.
            addOption("--retries", 10)
            addOption("--fragment-retries", 10)
            addOption("--socket-timeout", 30)
        }''',
    "ENGINE: retries for connection resets",
    already='addOption("--retries", 10)')

# ---------------------------------------------------------------------------
# Edit 47: HomeViewModel -- keep the link, the info card and the format
# selection after a download is queued: coming back from the Downloads
# tab shows the last video instead of a blank, reset page, and another
# quality of the same video can be queued right away.
# ---------------------------------------------------------------------------
apply_edit(VM_S,
    '''            Graph.db.downloadDao().insert(entity)
            DownloadService.start(getApplication())
            state = HomeUiState.Idle
            url = ""
            selectedVideoId = null
            selectedAudioId = null
            onQueued()''',
    '''            Graph.db.downloadDao().insert(entity)
            DownloadService.start(getApplication())
            // Patch 5: the link, the info card and the format selection
            // stay on the Home screen after a download is queued.
            onQueued()''',
    "VM: keep the link and info after queueing",
    already="Patch 5: the link, the info card and the format selection")

# ---------------------------------------------------------------------------
# Edit 48: Service -- a terminal log per download: the exact yt-dlp
# command line plus every output line (kept in the Room row), the byte
# counters parsed out of the "[download] 51.3% of 9.6MiB" lines, and
# the biggest non-part file picked after a merge.
# Non-ASCII chars (the ellipsis) are written as \\u2026 escapes so this
# script itself stays pure ASCII.
# ---------------------------------------------------------------------------
OLD_SVC_BLOCK = '''        updateNotification(item.title, "Starting\u2026", 0)

        try {
            Graph.awaitEngine()

            var lastPercent = -1
            Graph.engine.download(item.url, item.formatSelector, processId, template) { progress, eta, _ ->
                val percent = progress.toInt().coerceIn(0, 100)
                if (percent > lastPercent) {
                    lastPercent = percent
                    scope.launch {
                        dao.updateProgress(item.id, DownloadEntity.STATUS_RUNNING, progress, eta)
                        updateNotification(item.title, "Downloading\u2026 $percent%", percent)
                    }
                }
            }

            dao.setStatus(item.id, DownloadEntity.STATUS_SAVING)
            updateNotification(item.title, "Saving file\u2026", -1)

            val file = tempDir.listFiles()?.firstOrNull { it.isFile }
                ?: throw IllegalStateException("Downloaded file not found")

            val treeUri = Graph.settings.treeUri.first()
            val savedUri = FileSaver.save(this, treeUri, file)
            val mime = MimeUtils.fromFileName(file.name)

            if (savedUri == null) {
                dao.finishWithError(item.id, DownloadEntity.STATUS_FAILED, "Could not save the file to the selected folder")
            } else {
                dao.finish(item.id, savedUri.toString())
                showCompletedNotification(item.id, item.title, savedUri, mime)
            }
            tempDir.deleteRecursively()
        } catch (e: Exception) {
            val status = if (cancelCurrent) DownloadEntity.STATUS_CANCELED else DownloadEntity.STATUS_FAILED
            val message = if (cancelCurrent) null else (e.message ?: "Download failed").take(300)
            dao.finishWithError(item.id, status, message)
            tempDir.deleteRecursively()
        } finally {'''

NEW_SVC_BLOCK = '''        // Patch 5: terminal log -- the command line plus every yt-dlp
        // output line, shown by the terminal button on the Downloads tab.
        val log = StringBuilder()
        fun logLine(line: String) {
            if (line.isBlank()) return
            log.appendLine(line.trimEnd())
            if (log.length > 24000) {
                log.delete(0, log.length - 20000)
            }
        }

        updateNotification(item.title, "Starting\u2026", 0)
        logLine("\\$ yt-dlp --no-playlist -f '${item.formatSelector}' ${item.url}")

        try {
            Graph.awaitEngine()

            var lastPercent = -1
            Graph.engine.download(item.url, item.formatSelector, processId, template) { progress, eta, line ->
                if (line.isNotBlank()) {
                    logLine(line)
                }
                val percent = progress.toInt().coerceIn(0, 100)
                if (percent > lastPercent) {
                    lastPercent = percent
                    val bytes = parseProgressBytes(line)
                    val snapshot = log.toString()
                    scope.launch {
                        dao.updateProgress(
                            item.id, DownloadEntity.STATUS_RUNNING, progress, eta,
                            bytes?.first, bytes?.second, snapshot
                        )
                        updateNotification(item.title, "Downloading\u2026 $percent%", percent)
                    }
                }
            }
            dao.updateLog(item.id, log.toString())

            dao.setStatus(item.id, DownloadEntity.STATUS_SAVING)
            updateNotification(item.title, "Saving file\u2026", -1)

            val file = tempDir.listFiles()
                ?.filter { it.isFile && !it.name.endsWith(".part") && !it.name.endsWith(".ytdl") }
                ?.maxByOrNull { it.length() }
                ?: throw IllegalStateException("Downloaded file not found")

            val treeUri = Graph.settings.treeUri.first()
            val savedUri = FileSaver.save(this, treeUri, file)
            val mime = MimeUtils.fromFileName(file.name)

            if (savedUri == null) {
                dao.finishWithError(item.id, DownloadEntity.STATUS_FAILED, "Could not save the file to the selected folder")
                logLine("ERROR: could not save the file to the selected folder")
            } else {
                dao.finish(item.id, savedUri.toString())
                logLine("[ffmux] saved ${file.name} (${file.length()} bytes)")
                showCompletedNotification(item.id, item.title, savedUri, mime)
            }
            dao.updateLog(item.id, log.toString())
            tempDir.deleteRecursively()
        } catch (e: Exception) {
            val status = if (cancelCurrent) DownloadEntity.STATUS_CANCELED else DownloadEntity.STATUS_FAILED
            val message = if (cancelCurrent) null else (e.message ?: "Download failed").take(300)
            if (cancelCurrent) {
                logLine("[ffmux] canceled by user")
            } else {
                logLine("ERROR: ${e.message}")
            }
            dao.finishWithError(item.id, status, message)
            dao.updateLog(item.id, log.toString())
            tempDir.deleteRecursively()
        } finally {'''

apply_edit(SVC_S, OLD_SVC_BLOCK, NEW_SVC_BLOCK,
           "SERVICE: terminal log + byte counters + merge-safe file pick",
           already="Patch 5: terminal log -- the command line plus every yt-dlp")

# ---------------------------------------------------------------------------
# Edit 49: Service -- the progress-line parser (raw string: the regex
# keeps its backslashes).
# ---------------------------------------------------------------------------
apply_edit(SVC_S,
    '''    override fun onDestroy() {''',
    r'''    /** Reads "[download] 51.3% of 9.6MiB"-style lines into byte counts. */
    private val progressLine = Regex(
        """\[\s*download\s*\]\s+(\d+(?:\.\d+)?)%\s+of\s+~?\s*([\d.]+)\s*(KiB|MiB|GiB|TiB|KB|MB|GB|TB)"""
    )

    private fun parseProgressBytes(line: String): Pair<Long, Long>? {
        val m = progressLine.find(line) ?: return null
        val percent = m.groupValues[1].toDoubleOrNull() ?: return null
        val value = m.groupValues[2].toDoubleOrNull() ?: return null
        val unit = when (m.groupValues[3]) {
            "KiB" -> 1024.0
            "MiB" -> 1048576.0
            "GiB" -> 1073741824.0
            "TiB" -> 1099511627776.0
            "KB" -> 1000.0
            "MB" -> 1000000.0
            "GB" -> 1000000000.0
            "TB" -> 1000000000000.0
            else -> return null
        }
        val total = (value * unit).toLong()
        if (total <= 0L) return null
        val downloaded = (total * percent / 100.0).toLong()
        return downloaded to total
    }

    override fun onDestroy() {''',
    "SERVICE: progress-line byte parser",
    already="private fun parseProgressBytes")

# ---------------------------------------------------------------------------
# Edit 50: DownloadsViewModel -- retry() re-queues a failed download and
# restarts the service.
# ---------------------------------------------------------------------------
NEW_DLV = '''package com.ffmux.app.ui.downloads

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.ffmux.app.Graph
import com.ffmux.app.engine.DownloadService
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

class DownloadsViewModel(application: Application) : AndroidViewModel(application) {

    val items = Graph.db.downloadDao()
        .observeAll()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    fun cancel(id: Long) {
        DownloadService.cancel(getApplication(), id)
    }

    /** Puts a failed download back into the queue with the same link
     *  and the same format selector. */
    fun retry(id: Long) {
        viewModelScope.launch(Dispatchers.IO) {
            Graph.db.downloadDao().requeue(id)
            DownloadService.start(getApplication())
        }
    }

    fun delete(id: Long) {
        viewModelScope.launch(Dispatchers.IO) {
            Graph.db.downloadDao().delete(id)
        }
    }
}
'''
src = rd(DLV_S)
if "fun retry" in src:
    edits_skipped += 1
    print("  [skip]    DLVM: retry()")
elif "fun cancel" not in src or "fun delete" not in src:
    FAILED.append("DLVM: retry (unexpected base content)")
    print("  [FAIL]    DLVM: retry (unexpected base content)")
else:
    wr(DLV_S, NEW_DLV)
    edits_applied += 1
    print("  [applied] DLVM: retry()")

# ---------------------------------------------------------------------------
# Edit 51: Theme -- status bar icons follow the theme: dark icons on the
# light theme, light icons on the dark theme (the light theme used to
# show unreadable white icons).
# ---------------------------------------------------------------------------
NEW_THEME = '''package com.ffmux.app.ui.theme

import android.app.Activity
import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.core.view.WindowCompat

@Composable
fun FFMuxTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    dynamicColor: Boolean = true,
    content: @Composable () -> Unit
) {
    // Patch 5: dark status-bar icons on the light theme, light icons on
    // the dark theme, so the clock and the system icons stay readable.
    val view = LocalView.current
    if (!view.isInEditMode) {
        SideEffect {
            val window = (view.context as? Activity)?.window
            window?.let {
                WindowCompat.getInsetsController(it, view)
                    .isAppearanceLightStatusBars = !darkTheme
            }
        }
    }
    val colorScheme = when {
        dynamicColor && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {
            val context = LocalContext.current
            if (darkTheme) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        }
        darkTheme -> darkColorScheme()
        else -> lightColorScheme()
    }
    MaterialTheme(colorScheme = colorScheme, content = content)
}
'''
src = rd(THEME_S)
if "isAppearanceLightStatusBars" in src:
    edits_skipped += 1
    print("  [skip]    THEME: status bar icons follow the theme")
elif "fun FFMuxTheme" not in src:
    FAILED.append("THEME: rewrite (unexpected base content)")
    print("  [FAIL]    THEME: rewrite (unexpected base content)")
else:
    wr(THEME_S, NEW_THEME)
    edits_applied += 1
    print("  [applied] THEME: status bar icons follow the theme")

# ---------------------------------------------------------------------------
# Edit 52: DownloadsScreen -- full rewrite: a "Downloads" title with the
# terminal button next to it, the F-Droid style progress bar (dark-blue
# fill, green track, blue end dot, "4.9 MiB / 9.6 MiB" + "51%", grey
# cancel), a retry button on failed downloads and a full-screen terminal
# dialog with the colored log. Non-ASCII chars are \\uXXXX escapes.
# ---------------------------------------------------------------------------
NEW_SCREEN = '''package com.ffmux.app.ui.downloads

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Terminal
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.OpenInNew
import androidx.compose.material3.Card
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.ffmux.app.data.db.DownloadEntity

@Composable
fun DownloadsScreen(viewModel: DownloadsViewModel = viewModel()) {
    val items by viewModel.items.collectAsStateWithLifecycle()
    val context = LocalContext.current
    var showTerminal by remember { mutableStateOf(false) }

    Column(modifier = Modifier.fillMaxSize()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(start = 16.dp, end = 4.dp, top = 12.dp, bottom = 4.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text("Downloads", style = MaterialTheme.typography.headlineSmall)
            IconButton(onClick = { showTerminal = true }) {
                Icon(
                    Icons.Filled.Terminal,
                    contentDescription = "Terminal log",
                    modifier = Modifier.size(20.dp),
                    tint = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
        if (items.isEmpty()) {
            Box(modifier = Modifier.weight(1f), contentAlignment = Alignment.Center) {
                Text(
                    "No downloads yet.\\nShare a link from any app,\\nor paste one on the Home tab.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center
                )
            }
        } else {
            LazyColumn(
                modifier = Modifier.weight(1f),
                contentPadding = PaddingValues(
                    start = 16.dp, end = 16.dp, top = 4.dp, bottom = 16.dp
                ),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                items(items, key = { it.id }) { item ->
                    DownloadItemCard(
                        item = item,
                        onCancel = { viewModel.cancel(item.id) },
                        onDelete = { viewModel.delete(item.id) },
                        onOpen = {
                            item.savedUri?.let { openSavedFile(context, it) }
                        },
                        onRetry = { viewModel.retry(item.id) }
                    )
                }
            }
        }
    }
    if (showTerminal) {
        TerminalDialog(items = items, onDismiss = { showTerminal = false })
    }
}

@Composable
private fun DownloadItemCard(
    item: DownloadEntity,
    onCancel: () -> Unit,
    onDelete: () -> Unit,
    onOpen: () -> Unit,
    onRetry: () -> Unit
) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            Text(
                item.title,
                style = MaterialTheme.typography.titleSmall,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            Text(
                "${item.formatLabel} \u2022 ${statusText(item)}",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            when (item.status) {
                DownloadEntity.STATUS_QUEUED ->
                    DownloadProgressBlock(item = item, indeterminate = false, onCancel = onCancel)
                DownloadEntity.STATUS_RUNNING ->
                    DownloadProgressBlock(item = item, indeterminate = false, onCancel = onCancel)
                DownloadEntity.STATUS_SAVING ->
                    DownloadProgressBlock(item = item, indeterminate = true, onCancel = null)
                else -> {}
            }
            if (item.status == DownloadEntity.STATUS_FAILED) {
                item.error?.let { err ->
                    Text(
                        err,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.error,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis
                    )
                }
            }
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.End,
                verticalAlignment = Alignment.CenterVertically
            ) {
                if (item.status == DownloadEntity.STATUS_FAILED) {
                    IconButton(onClick = onRetry) {
                        Icon(Icons.Filled.Refresh, contentDescription = "Retry")
                    }
                }
                if (item.status == DownloadEntity.STATUS_COMPLETED) {
                    IconButton(onClick = onOpen) {
                        Icon(Icons.Outlined.OpenInNew, contentDescription = "Open")
                    }
                }
                IconButton(onClick = onDelete) {
                    Icon(Icons.Outlined.Delete, contentDescription = "Delete")
                }
            }
        }
    }
}

/** The F-Droid style row: "4.9 MiB / 9.6 MiB" on the left, "51%" on the
 *  right, the bar below and the grey cancel button on the right. */
@Composable
private fun DownloadProgressBlock(
    item: DownloadEntity,
    indeterminate: Boolean,
    onCancel: (() -> Unit)?
) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    progressLeftText(item, indeterminate),
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Spacer(Modifier.weight(1f))
                Text(
                    progressRightText(item, indeterminate),
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            FdroidProgressBar(
                progress = (item.progress / 100f).coerceIn(0f, 1f),
                indeterminate = indeterminate
            )
        }
        if (onCancel != null) {
            IconButton(onClick = onCancel) {
                Icon(
                    Icons.Filled.Close,
                    contentDescription = "Cancel",
                    tint = Color(0xFF9E9E9E),
                    modifier = Modifier.size(22.dp)
                )
            }
        }
    }
}

/** The F-Droid download bar: a dark-blue fill on a green track with a
 *  blue dot at the end of the bar. */
@Composable
private fun FdroidProgressBar(progress: Float, indeterminate: Boolean) {
    val fill = Color(0xFF015198)
    val track = Color(0xFF96BC19)
    val sweep = rememberInfiniteTransition(label = "fdroidSweep")
    val sweepPos by sweep.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(tween(1400, easing = LinearEasing)),
        label = "fdroidSweepPos"
    )
    Canvas(modifier = Modifier.fillMaxWidth().height(12.dp)) {
        val barHeight = 5.dp.toPx()
        val radius = barHeight / 2f
        val cy = size.height / 2f
        val dotRadius = 4.dp.toPx()
        val trackRight = size.width - dotRadius
        if (indeterminate) {
            drawRoundRect(
                color = track,
                topLeft = Offset(0f, cy - radius),
                size = Size(trackRight, barHeight),
                cornerRadius = CornerRadius(radius, radius)
            )
            drawCircle(
                color = fill,
                radius = dotRadius,
                center = Offset(sweepPos * trackRight, cy)
            )
        } else {
            val fillWidth = (trackRight * progress).coerceIn(0f, trackRight)
            if (fillWidth > 0f) {
                drawRoundRect(
                    color = fill,
                    topLeft = Offset(0f, cy - radius),
                    size = Size(fillWidth, barHeight),
                    cornerRadius = CornerRadius(radius, radius)
                )
            }
            val gap = 6.dp.toPx()
            val greenStart = fillWidth + gap
            if (greenStart < trackRight) {
                drawRoundRect(
                    color = track,
                    topLeft = Offset(greenStart, cy - radius),
                    size = Size(trackRight - greenStart, barHeight),
                    cornerRadius = CornerRadius(radius, radius)
                )
            }
            drawCircle(
                color = fill,
                radius = dotRadius,
                center = Offset(trackRight, cy)
            )
        }
    }
}

private fun progressLeftText(item: DownloadEntity, indeterminate: Boolean): String = when {
    item.status == DownloadEntity.STATUS_QUEUED -> "Queued"
    indeterminate -> "Saving\u2026"
    item.downloadedBytes != null && item.totalBytes != null ->
        formatBytes(item.downloadedBytes) + " / " + formatBytes(item.totalBytes)
    else -> "Downloading\u2026"
}

private fun progressRightText(item: DownloadEntity, indeterminate: Boolean): String = when {
    item.status == DownloadEntity.STATUS_QUEUED -> ""
    indeterminate -> ""
    item.progress > 0f -> item.progress.toInt().toString() + "%"
    else -> ""
}

/** 4.9 MiB / 9.6 MiB style, like the F-Droid download row. */
private fun formatBytes(bytes: Long): String {
    val kib = bytes / 1024.0
    val mib = kib / 1024.0
    val gib = mib / 1024.0
    return when {
        gib >= 1.0 -> String.format("%.1f GiB", gib)
        mib >= 10.0 -> String.format("%.0f MiB", mib)
        mib >= 1.0 -> String.format("%.1f MiB", mib)
        kib >= 1.0 -> String.format("%.0f KiB", kib)
        else -> bytes.toString() + " B"
    }
}

/** Full-screen terminal: the yt-dlp command and the output of every
 *  download, colored like a terminal. */
@Composable
private fun TerminalDialog(
    items: List<DownloadEntity>,
    onDismiss: () -> Unit
) {
    val logged = items.filter { !it.log.isNullOrBlank() }.sortedBy { it.id }
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .background(Color(0xFF0A0E0A))
                .systemBarsPadding()
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(start = 16.dp, end = 4.dp, top = 8.dp, bottom = 8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(
                    Icons.Filled.Terminal,
                    contentDescription = null,
                    tint = Color(0xFF8FD3A0),
                    modifier = Modifier.size(20.dp)
                )
                Spacer(Modifier.size(8.dp))
                Text(
                    "Terminal",
                    style = MaterialTheme.typography.titleMedium,
                    color = Color(0xFF8FD3A0),
                    fontFamily = FontFamily.Monospace
                )
                Spacer(Modifier.weight(1f))
                IconButton(onClick = onDismiss) {
                    Icon(Icons.Filled.Close, contentDescription = "Close", tint = Color(0xFFC6D6C6))
                }
            }
            if (logged.isEmpty()) {
                Text(
                    "No terminal output yet.\\nStart a download and come back.",
                    style = MaterialTheme.typography.bodySmall,
                    fontFamily = FontFamily.Monospace,
                    color = Color(0xFF7DA67D),
                    modifier = Modifier.padding(16.dp)
                )
            } else {
                val listState = rememberLazyListState()
                LazyColumn(
                    state = listState,
                    modifier = Modifier.weight(1f),
                    contentPadding = PaddingValues(
                        start = 16.dp, end = 16.dp, top = 4.dp, bottom = 16.dp
                    )
                ) {
                    logged.forEach { entry ->
                        item(key = "h" + entry.id) {
                            Text(
                                "-- # " + entry.id + " : " + entry.title +
                                    " [" + statusShort(entry) + "] --",
                                style = MaterialTheme.typography.labelMedium,
                                fontFamily = FontFamily.Monospace,
                                color = Color(0xFF6BD98A),
                                modifier = Modifier.padding(top = 10.dp, bottom = 4.dp)
                            )
                        }
                        entry.log.orEmpty().lines().forEachIndexed { i, line ->
                            item(key = "l" + entry.id + "_" + i) {
                                Text(
                                    line.ifBlank { " " },
                                    style = MaterialTheme.typography.bodySmall,
                                    fontFamily = FontFamily.Monospace,
                                    fontSize = 11.sp,
                                    color = logLineColor(line)
                                )
                            }
                        }
                    }
                }
                LaunchedEffect(logged.size, logged.lastOrNull()?.log?.length) {
                    val n = listState.layoutInfo.totalItemsCount
                    if (n > 0) {
                        listState.scrollToItem(n - 1)
                    }
                }
            }
        }
    }
}

private fun statusShort(item: DownloadEntity): String = when (item.status) {
    DownloadEntity.STATUS_QUEUED -> "QUEUED"
    DownloadEntity.STATUS_RUNNING -> "RUNNING"
    DownloadEntity.STATUS_SAVING -> "SAVING"
    DownloadEntity.STATUS_COMPLETED -> "COMPLETED"
    DownloadEntity.STATUS_CANCELED -> "CANCELED"
    DownloadEntity.STATUS_FAILED -> "FAILED"
    else -> item.status
}

private fun statusText(item: DownloadEntity): String = when (item.status) {
    DownloadEntity.STATUS_QUEUED -> "Queued"
    DownloadEntity.STATUS_RUNNING -> "Downloading"
    DownloadEntity.STATUS_SAVING -> "Saving"
    DownloadEntity.STATUS_COMPLETED -> "Completed"
    DownloadEntity.STATUS_CANCELED -> "Canceled"
    DownloadEntity.STATUS_FAILED -> "Failed"
    else -> item.status
}

private fun logLineColor(line: String): Color = when {
    line.startsWith("$") -> Color(0xFF7FD1FF)
    line.startsWith("ERROR", ignoreCase = true) -> Color(0xFFEF6C6C)
    line.contains("conversion failed", ignoreCase = true) -> Color(0xFFEF6C6C)
    line.startsWith("[download]") -> Color(0xFF8FD3A0)
    line.startsWith("[Merger]") || line.startsWith("[ExtractAudio]") -> Color(0xFF7FD1FF)
    else -> Color(0xFFC6D6C6)
}

private fun openSavedFile(context: Context, uriString: String) {
    val uri = Uri.parse(uriString)
    val intent = Intent(Intent.ACTION_VIEW).apply {
        setDataAndType(uri, "*/*")
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }
    runCatching { context.startActivity(intent) }
}
'''
src = rd(DLS_S)
if "TerminalDialog" in src:
    edits_skipped += 1
    print("  [skip]    DOWNLOADS: title + terminal + F-Droid bar + retry")
elif "DownloadItemCard" not in src or "openSavedFile" not in src:
    FAILED.append("DOWNLOADS: rewrite (unexpected base content)")
    print("  [FAIL]    DOWNLOADS: rewrite (unexpected base content)")
else:
    wr(DLS_S, NEW_SCREEN)
    edits_applied += 1
    print("  [applied] DOWNLOADS: title + terminal + F-Droid bar + retry")

# ---------------------------------------------------------------------------
# Edit 53: version bump -- smart, so it works on a fresh tree (1/1.0.0),
# on trees carrying patch 1 (2/1.0.1), patches 1+2 (3/1.0.2), patches
# 1+2+3 (4/1.1.0) or patches 1-4 (5/1.2.0), and skips when the tree is
# already at the target version (6/1.3.0).
# ---------------------------------------------------------------------------
src = rd(BUILD_G)
if "versionCode = 6" in src and 'versionName = "1.3.0"' in src:
    edits_skipped += 1
    print("  [skip]    BUILD: version already 1.3.0 (code 6)")
else:
    m_code = re.search(r"versionCode = (\d+)", src)
    m_name = re.search(r'versionName = "([^"]*)"', src)
    if not m_code or not m_name or int(m_code.group(1)) > 6:
        FAILED.append("BUILD: version bump (unexpected version state)")
        print("  [FAIL]    BUILD: version bump (unexpected version state)")
    else:
        new = re.sub(r"versionCode = \d+", "versionCode = 6", src, count=1)
        new = re.sub(r'versionName = "[^"]*"', 'versionName = "1.3.0"', new, count=1)
        wr(BUILD_G, new)
        edits_applied += 1
        print("  [applied] BUILD: bump versionCode ->6, versionName ->1.3.0")

print("  edits applied: " + str(edits_applied) + ", skipped: " + str(edits_skipped))
if FAILED:
    print("EDITS FAILED: " + "; ".join(FAILED))
    sys.exit(1)

# ===========================================================================
# Gates
# ===========================================================================
passed = 0
failed = 0

def gate(label, ok, note=""):
    global passed, failed
    if ok:
        passed += 1
        print("  [gate ok] " + label)
    else:
        failed += 1
        print("  [GATE FAIL] " + label + (" -> " + note if note else ""))

def cntf(p, needle):
    return rd(p).count(needle)

home = rd(HOME_S)
settings = rd(SET_S)
root = rd(ROOT_S)

# -- gate group 1: the Seal-style card + editable names -----------------------
gate("HOME: Seal-style info card present",
     cntf(HOME_S, "ElevatedCard(") == 1
     and cntf(HOME_S, "aspectRatio(16f / 9f, matchHeightConstraintsFirst = true)") == 1)
gate("HOME: duration badge bottom-end, black 68%, white text",
     cntf(HOME_S, ".align(Alignment.BottomEnd)") == 1
     and cntf(HOME_S, "Color.Black.copy(alpha = 0.68f)") == 1
     and cntf(HOME_S, "color = Color.White") == 1)
gate("HOME: duration font scales with screen (12-18sp)",
     cntf(HOME_S, "config.screenWidthDp * 0.038f") == 1
     and cntf(HOME_S, "coerceIn(12f, 18f)") == 1
     and cntf(HOME_S, "fontWeight = FontWeight.Medium") == 1
     and cntf(HOME_S, "fontSize = durationFontSize") == 1)
gate("HOME: title and author are editable fields",
     cntf(HOME_S, 'label = { Text("Title") }') == 1
     and cntf(HOME_S, 'label = { Text("Author") }') == 1
     and cntf(HOME_S, "Icons.Outlined.Edit") == 1
     and cntf(HOME_S, "onTitleChange: (String) -> Unit") == 1
     and cntf(HOME_S, "onUploaderChange: (String) -> Unit") == 1)
gate("HOME: Best card pinned above the video and audio sections",
     cntf(HOME_S, "option = current.catalog.best,") == 1
     and cntf(HOME_S, "chunked(2)") == 2
     and cntf(HOME_S, "private fun FormatCard(") == 1)
gate("HOME: Seal audio/video marks and animated selection colors",
     cntf(HOME_S, "Icons.Rounded.Videocam") == 1
     and cntf(HOME_S, "Icons.Rounded.Audiotrack") == 1
     and cntf(HOME_S, "animateColorAsState") == 4
     and "\\u00B7" in home)
gate("HOME: radio list and old card bits gone",
     "RadioButton" not in home
     and "width(120.dp)" not in home
     and "RoundedCornerShape" not in home
     and "import androidx.compose.material3.Card\n" not in home)

# -- gate group 2: settings ---------------------------------------------------
gate("SETTINGS: About card gone",
     'Text("About"' not in settings
     and "UI inspired by Seal" not in settings)
gate("SETTINGS: both remaining cards intact",
     cntf(SET_S, "Card(modifier = Modifier.fillMaxWidth())") == 2)

# -- gate group 3: the sliding pill nav bar ----------------------------------
gate("ROOT: stock NavigationBar gone",
     "NavigationBar" not in root)
gate("ROOT: sliding pill present",
     cntf(ROOT_S, "SlidingPillNavBar") == 2
     and cntf(ROOT_S, "MaterialTheme.colorScheme.secondaryContainer") == 1)
gate("ROOT: pill layer mirrors tab layer",
     cntf(ROOT_S, "LabelSlotHeight") == 3
     and cntf(ROOT_S, "weight(1f)") == 3)
gate("ROOT: bounce keyframes fast (280ms)",
     cntf(ROOT_S, "0.78f at 100 using FastOutSlowInEasing") == 1
     and cntf(ROOT_S, "durationMillis = 280") == 1)
gate("ROOT: page crossfade fast (150 in / 100 out)",
     cntf(ROOT_S, "fadeIn(tween(150))") == 2
     and cntf(ROOT_S, "fadeOut(tween(100))") == 2)
gate("ROOT: pill spring settles quickly (stiffness Medium)",
     "StiffnessMediumLow" not in root
     and cntf(ROOT_S, "Spring.StiffnessMedium\n") == 1)
gate("ROOT: no press ripple on tabs",
     cntf(ROOT_S, "indication = null") == 1
     and cntf(ROOT_S, "remember { MutableInteractionSource() }") == 1)
gate("ROOT: NavHost destinations intact",
     'composable("home")' in root
     and 'composable("downloads")' in root
     and 'composable("settings")' in root)

# -- gate group 4: view model wiring ------------------------------------------
gate("VM: editable title/uploader state with setters",
     cntf(VM_S, "var editableTitle by mutableStateOf") == 1
     and cntf(VM_S, "var editableUploader by mutableStateOf") == 1
     and cntf(VM_S, "fun updateTitle") == 1
     and cntf(VM_S, "fun updateUploader") == 1)
gate("VM: names filled on fetch and used for the download",
     cntf(VM_S, 'editableTitle = info.title ?: "Untitled"') == 1
     and cntf(VM_S, 'editableUploader = info.uploader ?: ""') == 1
     and cntf(VM_S, "title = editableTitle.ifBlank") == 1
     and cntf(VM_S, "uploader = editableUploader.ifBlank") == 1)

# -- gate group 5: engine -------------------------------------------------------
gate("ENGINE: Best card with the merge selector on top of the catalog",
     cntf(ENG_S, 'label = "Best"') == 1
     and cntf(ENG_S, "bestvideo*+bestaudio/best") == 1
     and cntf(ENG_S, 'note = "Best video + best audio, merged"') == 1
     and cntf(ENG_S, "return FormatCatalog(") == 1)
gate("ENGINE: spec metadata (ext / fps / kbps / size) computed",
     cntf(ENG_S, "fun estimatedBytes") == 1
     and cntf(ENG_S, "fun sizeText") == 1
     and cntf(ENG_S, "fun addSizes") == 1)
gate("ENGINE: youtubedl-android 0.18.1 null-safety fix in place",
     cntf(ENG_S, '.getOrNull() ?: "unknown"') == 1
     and cntf(ENG_S, 'else -> "yt-dlp is already up to date."') == 1)

# -- gate group 6: models --------------------------------------------------------
gate("MODELS: FormatOption carries format specs",
     cntf(MOD_S, "val kind: FormatKind,\n    val ext: String? = null") == 1
     and cntf(MOD_S, "val fps: Int? = null") == 1
     and cntf(MOD_S, "val kbps: Int? = null") == 1
     and cntf(MOD_S, "val size: String? = null") == 1
     and cntf(MOD_S, "val note: String? = null") == 1)

# -- gate group 7: service --------------------------------------------------------
gate("SERVICE: saved file name follows the editable title",
     cntf(SVC_S, "val safeTitle = item.title") == 1
     and cntf(SVC_S, "Regex(") >= 1
     and "%(title).80s" not in rd(SVC_S)
     and "[%(id)s]" not in rd(SVC_S))

# -- gate group 8: patch 4 -- split catalog, merge selection, pinned button
gate("HOME: video and audio streams listed apart",
     cntf(HOME_S, 'Text("Video", style = MaterialTheme.typography.titleSmall)') == 1
     and cntf(HOME_S, 'Text("Audio", style = MaterialTheme.typography.titleSmall)') == 1
     and cntf(HOME_S, "viewModel.toggleVideo(option)") == 1
     and cntf(HOME_S, "viewModel.toggleAudio(option)") == 1
     and "forEachIndexed" not in home
     and "selectedFormat" not in home)
gate("HOME: cards show id, resolution, fps, container, bitrate, size",
     cntf(HOME_S, "private fun formatSpecLine1(") == 1
     and cntf(HOME_S, "private fun formatSpecLine2(") == 1
     and cntf(HOME_S, '"ID " + option.id') == 1
     and "\\u00D7" in home
     and "\\u2248" in home)
gate("HOME: download button pinned below the scrolling list",
     cntf(HOME_S, ".weight(1f)\n                .verticalScroll(") == 1
     and cntf(HOME_S, "Icons.Filled.Download") == 1
     and cntf(HOME_S, ".height(52.dp)") == 1
     and cntf(HOME_S, "viewModel.startDownload(onDownloadStarted)") == 1)
gate("HOME: estimated final size on the download button",
     cntf(HOME_S, "resolveSizeBytes") == 1
     and cntf(HOME_S, '"Download audio"') == 2
     and cntf(HOME_S, "private fun formatSize(") == 1)
gate("VM: video+audio selection with merge resolution",
     cntf(VM_S, "var selectedVideoId by mutableStateOf") == 1
     and cntf(VM_S, "var selectedAudioId by mutableStateOf") == 1
     and cntf(VM_S, "fun resolveSelector(") == 1
     and cntf(VM_S, "fun resolveLabel(") == 1
     and cntf(VM_S, "fun resolveSizeBytes(") == 1
     and "selectedFormat" not in rd(VM_S))
gate("ENGINE: every stream listed with its own format id",
     cntf(ENG_S, "fun buildFormatOptions(info: VideoInfo): FormatCatalog") == 1
     and cntf(ENG_S, "distinctBy { it.formatId }") == 2
     and cntf(ENG_S, "hasAudio = !f.acodec.isNullOrEmpty() && f.acodec != \"none\"") == 1)
gate("MODELS: catalog fields",
     cntf(MOD_S, "data class FormatCatalog(") == 1
     and cntf(MOD_S, "val sizeBytes: Long? = null") == 1
     and cntf(MOD_S, "val hasAudio: Boolean = false") == 1
     and cntf(MOD_S, "val isBest: Boolean = false") == 1
     and cntf(MOD_S, "val width: Int? = null") == 2)

# -- gate group 9: patch 5 -- sticky link, retries, terminal log, F-Droid bar, retry
gate("VM: the link and the info stay after a download is queued",
     'url = ""' not in rd(VM_S)
     and "Patch 5: the link, the info card and the format selection" in rd(VM_S))
gate("ENGINE: retries for connection resets (errno 104)",
     cntf(ENG_S, 'addOption("--retries", 10)') == 1
     and cntf(ENG_S, 'addOption("--fragment-retries", 10)') == 1
     and cntf(ENG_S, 'addOption("--socket-timeout", 30)') == 1)
gate("DB: bytes + log columns and a real 1->2 migration",
     cntf(ENT_S, "val downloadedBytes: Long? = null") == 1
     and cntf(ENT_S, "val totalBytes: Long? = null") == 1
     and cntf(ENT_S, "val log: String? = null") == 1
     and cntf(ADB_S, "version = 2") == 1
     and cntf(GR_S, ".addMigrations(AppDatabase.MIGRATION_1_2)") == 1)
gate("DAO: progress carries bytes + log, requeue for retry",
     cntf(DAO_S, "downloadedBytes = :downloaded") == 1
     and cntf(DAO_S, "downloadedBytes = NULL") == 2
     and cntf(DAO_S, "suspend fun requeue") == 1)
gate("SERVICE: terminal log captured per download",
     cntf(SVC_S, "val log = StringBuilder()") == 1
     and cntf(SVC_S, "fun logLine") == 1
     and cntf(SVC_S, "dao.updateLog") == 3
     and cntf(SVC_S, "private fun parseProgressBytes") == 1)
gate("SERVICE: biggest non-part file picked after a merge",
     cntf(SVC_S, ".maxByOrNull { it.length() }") == 1
     and cntf(SVC_S, '.endsWith(".part")') == 1)
gate("DOWNLOADS: title bar with the terminal button",
     cntf(DLS_S, 'Text("Downloads", style = MaterialTheme.typography.headlineSmall)') == 1
     and cntf(DLS_S, "Icons.Filled.Terminal") == 2)
gate("DOWNLOADS: F-Droid progress bar (blue fill, green track, end dot)",
     cntf(DLS_S, "private fun FdroidProgressBar(") == 1
     and "Color(0xFF015198)" in rd(DLS_S)
     and "Color(0xFF96BC19)" in rd(DLS_S)
     and cntf(DLS_S, "drawRoundRect") == 3
     and cntf(DLS_S, "drawCircle") == 2
     and cntf(DLS_S, "val gap = 6.dp.toPx()") == 1)
gate("DOWNLOADS: size + percent row and retry button",
     cntf(DLS_S, "private fun formatBytes(") == 1
     and '" / "' in rd(DLS_S)
     and cntf(DLS_S, "Icons.Filled.Refresh") == 1
     and cntf(DLV_S, ".requeue(id)") == 1)
gate("DOWNLOADS: terminal dialog with monospace colored log",
     cntf(DLS_S, "private fun TerminalDialog(") == 1
     and cntf(DLS_S, "usePlatformDefaultWidth = false") == 1
     and cntf(DLS_S, "FontFamily.Monospace") >= 3
     and cntf(DLS_S, "private fun logLineColor(") == 1)
gate("THEME: status bar icons follow the theme",
     cntf(THEME_S, "isAppearanceLightStatusBars = !darkTheme") == 1
     and cntf(THEME_S, "WindowCompat.getInsetsController") == 1)

# -- gate group: version ------------------------------------------------------
gate("BUILD: version 1.3.0 / code 6",
     "versionCode = 6" in rd(BUILD_G)
     and 'versionName = "1.3.0"' in rd(BUILD_G))

# -- gate group: kotlin-lite brace/paren balance ------------------------------
def scan(src):
    errs = []
    depth = 0
    paren = 0
    stack = [("code", 0)]
    line = 1
    i = 0
    n = len(src)
    while i < n:
        ch = src[i]
        nxt = src[i + 1] if i + 1 < n else ""
        if ch == "\n":
            line += 1
            i += 1
            continue
        top = stack[-1][0]
        if top == "str":
            if ch == "\\":
                i += 2
                continue
            if ch == '"':
                stack.pop()
            i += 1
            continue
        if top == "char":
            if ch == "\\":
                i += 2
                continue
            if ch == "'":
                stack.pop()
            i += 1
            continue
        if top == "tpl":
            if ch == "{":
                stack[-1] = ("tpl", stack[-1][1] + 1)
            elif ch == "}":
                if stack[-1][1] == 0:
                    stack.pop()
                    depth -= 1
                else:
                    stack[-1] = ("tpl", stack[-1][1] - 1)
            i += 1
            continue
        if ch == "/" and nxt == "/":
            while i < n and src[i] != "\n":
                i += 1
            continue
        if ch == "/" and nxt == "*":
            i += 2
            while i + 1 < n and not (src[i] == "*" and src[i + 1] == "/"):
                if src[i] == "\n":
                    line += 1
                i += 1
            i += 2
            continue
        if ch == '"':
            stack.append(("str", 0))
            i += 1
            continue
        if ch == "'":
            stack.append(("char", 0))
            i += 1
            continue
        if ch == "$" and nxt == "{":
            stack.append(("tpl", 0))
            depth += 1
            i += 2
            continue
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth < 0:
                errs.append("line " + str(line) + ": unbalanced }")
        elif ch == "(":
            paren += 1
        elif ch == ")":
            paren -= 1
            if paren < 0:
                errs.append("line " + str(line) + ": unbalanced )")
        i += 1
    if depth != 0:
        errs.append("final brace depth " + str(depth))
    if paren != 0:
        errs.append("final paren depth " + str(paren))
    if len(stack) != 1 or stack[-1][0] != "code":
        errs.append("unclosed literal: " + str(stack))
    return errs

for p in [HOME_S, SET_S, ROOT_S, VM_S, ENG_S, MOD_S, SVC_S, ENT_S, ADB_S, DAO_S, GR_S, DLS_S, DLV_S, THEME_S]:
    errs = scan(rd(p))
    gate("kotlin-lite brace/paren balance: " + p, not errs, "; ".join(errs[:3]))

if failed:
    print("GATES FAILED: " + str(failed) + " of " + str(failed + passed))
    sys.exit(1)
print("ALL GATES GREEN (" + str(passed) + " checks)")
PYEOF
echo "== patches 1+2+3+4+5 done =="
