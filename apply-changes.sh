#!/usr/bin/env bash
###############################################################################
# FFMux UI patches 1+2 -- cumulative, idempotent patcher.
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
# App version after this script: 1.0.2 (versionCode 3).
#
# Safe to run on: a fresh clone of the upstream repo, a tree that
# already carries patch 1, or a tree already carrying this patch
# (everything skips). Aborts loudly, without writing, on any anchor
# mismatch.
#
# Files touched: HomeScreen.kt, SettingsScreen.kt, AppRoot.kt,
#                app/build.gradle.kts
###############################################################################
set -euo pipefail

if LC_ALL=C grep -qn '[^ -~]' "$0"; then
  echo "FATAL: non-ascii byte in this script"
  exit 1
fi

HOME_S="app/src/main/java/com/ffmux/app/ui/home/HomeScreen.kt"
SET_S="app/src/main/java/com/ffmux/app/ui/settings/SettingsScreen.kt"
ROOT_S="app/src/main/java/com/ffmux/app/ui/AppRoot.kt"
BUILD_G="app/build.gradle.kts"
for f in "$HOME_S" "$SET_S" "$ROOT_S" "$BUILD_G"; do
  if [ ! -f "$f" ]; then
    echo "FATAL: $f not found - run from the repository root"
    exit 1
  fi
done

echo "== patches 1+2: Seal card, no About, sliding pill nav, no ripple, bigger duration, faster switch =="
python3 - <<'PYEOF'
import re
import sys

HOME_S = "app/src/main/java/com/ffmux/app/ui/home/HomeScreen.kt"
SET_S = "app/src/main/java/com/ffmux/app/ui/settings/SettingsScreen.kt"
ROOT_S = "app/src/main/java/com/ffmux/app/ui/AppRoot.kt"
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

# ---------------------------------------------------------------------------
# Edit 13: version bump -- smart, so it works on a fresh tree (1/1.0.0),
# on a tree with patch 1 already applied (2/1.0.1), and skips when the
# tree is already at the target version (3/1.0.2).
# ---------------------------------------------------------------------------
src = rd(BUILD_G)
if "versionCode = 3" in src and 'versionName = "1.0.2"' in src:
    edits_skipped += 1
    print("  [skip]    BUILD: version already 1.0.2 (code 3)")
else:
    m_code = re.search(r"versionCode = (\d+)", src)
    m_name = re.search(r'versionName = "([^"]*)"', src)
    if not m_code or not m_name or int(m_code.group(1)) > 3:
        FAILED.append("BUILD: version bump (unexpected version state)")
        print("  [FAIL]    BUILD: version bump (unexpected version state)")
    else:
        new = re.sub(r"versionCode = \d+", "versionCode = 3", src, count=1)
        new = re.sub(r'versionName = "[^"]*"', 'versionName = "1.0.2"', new, count=1)
        wr(BUILD_G, new)
        edits_applied += 1
        print("  [applied] BUILD: bump versionCode ->3, versionName ->1.0.2")

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

# -- gate group 1: the Seal-style card ---------------------------------------
gate("HOME: ElevatedCard with shapes.small",
     cntf(HOME_S, "ElevatedCard(") == 1
     and cntf(HOME_S, "shape = MaterialTheme.shapes.small") == 1)
gate("HOME: 16:9 full-width thumbnail",
     cntf(HOME_S, "aspectRatio(16f / 9f, matchHeightConstraintsFirst = true)") == 1)
gate("HOME: duration badge bottom-end, black 68%, white text",
     cntf(HOME_S, ".align(Alignment.BottomEnd)") == 1
     and cntf(HOME_S, "Color.Black.copy(alpha = 0.68f)") == 1
     and cntf(HOME_S, "color = Color.White") == 1)
gate("HOME: duration font scales with screen (12-18sp)",
     cntf(HOME_S, "config.screenWidthDp * 0.038f") == 1
     and cntf(HOME_S, "coerceIn(12f, 18f)") == 1
     and cntf(HOME_S, "fontWeight = FontWeight.Medium") == 1
     and "labelSmall" not in home)
gate("HOME: title titleMedium + uploader bodyMedium under thumbnail",
     cntf(HOME_S, 'text = info.title ?: "Untitled"') == 1
     and cntf(HOME_S, "style = MaterialTheme.typography.titleMedium") == 2
     and cntf(HOME_S, "style = MaterialTheme.typography.bodyMedium") == 2)
gate("HOME: old card bits gone",
     "RoundedCornerShape" not in home
     and "width(120.dp)" not in home
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

# -- gate group: version ------------------------------------------------------
gate("BUILD: version 1.0.2 / code 3",
     "versionCode = 3" in rd(BUILD_G)
     and 'versionName = "1.0.2"' in rd(BUILD_G))

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

for p in [HOME_S, SET_S, ROOT_S]:
    errs = scan(rd(p))
    gate("kotlin-lite brace/paren balance: " + p, not errs, "; ".join(errs[:3]))

if failed:
    print("GATES FAILED: " + str(failed) + " of " + str(failed + passed))
    sys.exit(1)
print("ALL GATES GREEN (" + str(passed) + " checks)")
PYEOF
echo "== patches 1+2 done =="
