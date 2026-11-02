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
# App version after this script: 1.1.0 (versionCode 4).
#
# Safe to run on: a fresh clone of the upstream repo, a tree that
# already carries patch 1, patches 1+2, or this patch (everything
# skips). Aborts loudly, without writing, on any anchor mismatch.
#
# Files touched: HomeScreen.kt, HomeViewModel.kt, SettingsScreen.kt,
#                AppRoot.kt, YtDlpEngine.kt, Models.kt,
#                DownloadService.kt, app/build.gradle.kts
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
BUILD_G="app/build.gradle.kts"
for f in "$HOME_S" "$VM_S" "$SET_S" "$ROOT_S" "$ENG_S" "$MOD_S" "$SVC_S" "$BUILD_G"; do
  if [ ! -f "$f" ]; then
    echo "FATAL: $f not found - run from the repository root"
    exit 1
  fi
done

echo "== patches 1+2+3: Seal card, editable names, format cards + Best, pill nav, no ripple, faster switch =="
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
           already="listOf(best) + video + audioOptions")

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
           already="current.options.chunked(2)")

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

# ---------------------------------------------------------------------------
# Edit 26: version bump -- smart, so it works on a fresh tree (1/1.0.0),
# on trees carrying patch 1 (2/1.0.1) or patches 1+2 (3/1.0.2), and
# skips when the tree is already at the target version (4/1.1.0).
# ---------------------------------------------------------------------------
src = rd(BUILD_G)
if "versionCode = 4" in src and 'versionName = "1.1.0"' in src:
    edits_skipped += 1
    print("  [skip]    BUILD: version already 1.1.0 (code 4)")
else:
    m_code = re.search(r"versionCode = (\d+)", src)
    m_name = re.search(r'versionName = "([^"]*)"', src)
    if not m_code or not m_name or int(m_code.group(1)) > 4:
        FAILED.append("BUILD: version bump (unexpected version state)")
        print("  [FAIL]    BUILD: version bump (unexpected version state)")
    else:
        new = re.sub(r"versionCode = \d+", "versionCode = 4", src, count=1)
        new = re.sub(r'versionName = "[^"]*"', 'versionName = "1.1.0"', new, count=1)
        wr(BUILD_G, new)
        edits_applied += 1
        print("  [applied] BUILD: bump versionCode ->4, versionName ->1.1.0")

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
     cntf(HOME_S, ".align(Alignment.BottomEnd)") == 2
     and cntf(HOME_S, "Color.Black.copy(alpha = 0.68f)") == 1
     and cntf(HOME_S, "color = Color.White") == 1)
gate("HOME: duration font scales with screen (12-18sp)",
     cntf(HOME_S, "config.screenWidthDp * 0.038f") == 1
     and cntf(HOME_S, "coerceIn(12f, 18f)") == 1
     and cntf(HOME_S, "fontWeight = FontWeight.Medium") == 1
     and "labelSmall" not in home)
gate("HOME: title and author are editable fields",
     cntf(HOME_S, 'label = { Text("Title") }') == 1
     and cntf(HOME_S, 'label = { Text("Author") }') == 1
     and cntf(HOME_S, "Icons.Outlined.Edit") == 1
     and cntf(HOME_S, "onTitleChange: (String) -> Unit") == 1
     and cntf(HOME_S, "onUploaderChange: (String) -> Unit") == 1)
gate("HOME: format cards in a two-column grid, Best pinned first",
     cntf(HOME_S, "chunked(2)") == 1
     and cntf(HOME_S, "isBest = index == 0") == 1
     and cntf(HOME_S, "private fun FormatCard(") == 1
     and cntf(HOME_S, "private fun formatSpec(") == 1)
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
gate("ENGINE: Best pinned above every other quality",
     cntf(ENG_S, 'label = "Best"') == 1
     and cntf(ENG_S, "bestvideo*+bestaudio/best") == 1
     and cntf(ENG_S, "listOf(best) + video + audioOptions") == 1
     and cntf(ENG_S, 'note = "Best video + audio"') == 1)
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
     and cntf(SVC_S, "Regex(") == 1
     and "%(title).80s" not in rd(SVC_S)
     and "[%(id)s]" not in rd(SVC_S))

# -- gate group: version ------------------------------------------------------
gate("BUILD: version 1.1.0 / code 4",
     "versionCode = 4" in rd(BUILD_G)
     and 'versionName = "1.1.0"' in rd(BUILD_G))

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

for p in [HOME_S, SET_S, ROOT_S, VM_S, ENG_S, MOD_S, SVC_S]:
    errs = scan(rd(p))
    gate("kotlin-lite brace/paren balance: " + p, not errs, "; ".join(errs[:3]))

if failed:
    print("GATES FAILED: " + str(failed) + " of " + str(failed + passed))
    sys.exit(1)
print("ALL GATES GREEN (" + str(passed) + " checks)")
PYEOF
echo "== patches 1+2+3 done =="
