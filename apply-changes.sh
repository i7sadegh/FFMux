#!/usr/bin/env bash
set -euo pipefail

# =====================================================================
# FFMux patch 26  ->  v1.4.19 (versionCode 26)
#
# Four changes, all requested:
#  1. In the Author row: Author comes FIRST (left), Ext comes SECOND
#     (right) -- the order of patch 25 was the wrong way around.
#  2. When a link fetch fails, the red reset ("start over") button is
#     shown UNDER the big circular blue button, with the same effect
#     as the reset button in the sticky download bar.
#  3. The Downloads tab list always opens at the TOP: while a download
#     runs (the newest item is first), the tab no longer restores an
#     old scroll position -- it scrolls to the first item on entry.
#  4. The trash button on a COMPLETED download asks before deleting:
#     "Delete from list" or "Delete file + list" (the second one also
#     deletes the saved file from storage -- yes, this is possible).
#
# Nothing else is added or removed. No file under .github/ is touched.
# Safe mode: sha256 baselines verified before and after, every
# replacement anchored and counted, and the run is idempotent.
# =====================================================================

cd "$(dirname "$0")"

echo "== FFMux patch 26 (v1.4.19) =="

HOME="app/src/main/java/com/ffmux/app/ui/home/HomeScreen.kt"
DS="app/src/main/java/com/ffmux/app/ui/downloads/DownloadsScreen.kt"
DVM="app/src/main/java/com/ffmux/app/ui/downloads/DownloadsViewModel.kt"
GRADLE="app/build.gradle.kts"

# ---------------------------------------------------------------------
# Already patched (hash-verified)?  Then this is a no-op.
# ---------------------------------------------------------------------
hash_is() {
    [ "$(sha256sum "$1" 2>/dev/null | awk '{print $1}')" = "$2" ]
}

if hash_is "$HOME" a7ec87da68617e164ada232aa77c90210714db0de721b08edf52589a95ee6546 && hash_is "$DS" a66c6c4cf2481745e10edfc7bc70a50ec2cd04df94801ff63a780ed763c77fb8 && \
   hash_is "$DVM" 1a91d3cff7d940444fa885aa199fe7fb2cb3a934948d1118bf9031749a984d0d && hash_is "$GRADLE" 375164bfa222472811c9c7facd436b84e26e077e3e78dafc47a8acc75acecb7f; then
    echo "Already patched (hashes verified) -- nothing to do."
    exit 0
fi

# ---------------------------------------------------------------------
# Baseline check: the tree must be exactly the post-patch-25 state
# (v1.4.18 committed as 36712cd).
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
        echo "The repository is not in the expected post-patch-25 (v1.4.18) state."
        exit 1
    fi
}

verify "$HOME"   2a030d29465a3ab06446eeb1de857fbf0347b32d0310950700a610016bc72765
verify "$DS"     b2753a8d1257b131cdc71d433620f250f828929b5f8d2b668f4fc5507d9b025b
verify "$DVM"    48b9e67a3c07732375234032b4470742b8fa8888a6e42e9da9c7478d38ea91a5
verify "$GRADLE" 6b5f70246f87e132bfea424630dd34339f1ddc22d8e0c4378fda6023ed59099a

echo "Baselines verified (post patch 25)."

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
# HomeScreen.kt -- (1) Author first, Ext second
#                  (2) red reset button under the blue button on error
# =====================================================================
HOME = "app/src/main/java/com/ffmux/app/ui/home/HomeScreen.kt"

HOME_PAIRS = [
    # --- (1) swap the order in the Author row -----------------------
    ("""                Spacer(Modifier.height(8.dp))
                // Ext picker at the head of the Author row, as ordered:
                // the final container of a merged video+audio download,
                // the "ext" part of the yt-dlp command
                // (--merge-output-format). Default mp4; the menu offers
                // mp4 / mkv / mov.
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    ExtDropdown(
                        selected = mergeExt,
                        onSelected = onMergeExtChange
                    )
                    Spacer(Modifier.width(8.dp))
                    OutlinedTextField(
                        value = uploader,
                        onValueChange = onUploaderChange,
                        modifier = Modifier.weight(1f),
                        label = { Text("Author") },
                        singleLine = true,
                        textStyle = MaterialTheme.typography.bodyMedium,
                        shape = MaterialTheme.shapes.small
                    )
                }
""",
     """                Spacer(Modifier.height(8.dp))
                // Author first (left), Ext second (right), as ordered:
                // the Author input takes the remaining width, the Ext
                // picker -- the final container of a merged download,
                // i.e. the "ext" part of the yt-dlp command
                // (--merge-output-format, default mp4, menu mp4/mkv/mov)
                // -- sits at the end of the row.
                Row(
                    modifier = Modifier.fillMaxWidth(),
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
                    ExtDropdown(
                        selected = mergeExt,
                        onSelected = onMergeExtChange
                    )
                }
""", 1),
    # --- (2) red reset button under the circular button on error ----
    ("""                    CircularFetchButton(loading = loading, onClick = onFetchClicked)
                    if (errorState != null) {
                        Spacer(Modifier.height(20.dp))
                        Text(
                            text = errorState.message,
                            color = MaterialTheme.colorScheme.error,
                            style = MaterialTheme.typography.bodyMedium,
                            textAlign = TextAlign.Center
                        )
                    }
""",
     """                    CircularFetchButton(loading = loading, onClick = onFetchClicked)
                    if (errorState != null) {
                        Spacer(Modifier.height(20.dp))
                        Text(
                            text = errorState.message,
                            color = MaterialTheme.colorScheme.error,
                            style = MaterialTheme.typography.bodyMedium,
                            textAlign = TextAlign.Center
                        )
                        // The same red "start over" action as the reset
                        // button in the sticky download bar, placed right
                        // under the big button when a fetch failed.
                        Spacer(Modifier.height(16.dp))
                        val resetInteraction = remember { MutableInteractionSource() }
                        FilledTonalIconButton(
                            onClick = onReset,
                            interactionSource = resetInteraction,
                            modifier = rememberPressScale(resetInteraction)
                                .size(52.dp),
                            shape = MaterialTheme.shapes.large,
                            colors = IconButtonDefaults.filledTonalIconButtonColors(
                                containerColor = Color(0xFFD32F2F),
                                contentColor = Color(0xFFFFFFFF)
                            )
                        ) {
                            Icon(
                                imageVector = Icons.Rounded.Close,
                                contentDescription = "Clear the failed link",
                                modifier = Modifier.size(24.dp)
                            )
                        }
                    }
""", 1),
    # --- (2b) the error page block needs onReset passed down --------
    ("""            Box(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth(),
                contentAlignment = Alignment.Center
            ) {
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    modifier = Modifier.padding(horizontal = 24.dp)
                ) {
""",
     """            Box(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth(),
                contentAlignment = Alignment.Center
            ) {
                val onReset = remember(viewModel) { { viewModel.resetScreen() } }
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    modifier = Modifier.padding(horizontal = 24.dp)
                ) {
""", 1),
]

patch(HOME, HOME_PAIRS)

# =====================================================================
# DownloadsScreen.kt -- (3) list opens at the top
#                       (4) trash asks: list only / file + list
# =====================================================================
DS = "app/src/main/java/com/ffmux/app/ui/downloads/DownloadsScreen.kt"

DS_PAIRS = [
    # --- imports -----------------------------------------------------
    ("""import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
""",
     """import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
""", 1),
    ("""import androidx.compose.material3.Card
import androidx.compose.material3.Icon
""",
     """import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.Icon
""", 1),
    ("""import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
""",
     """import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
""", 1),
    # --- (3)+(4) list state: always start at the top; pending delete --
    ("""            LazyColumn(
                modifier = Modifier.weight(1f),
                contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 4.dp, bottom = 16.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
""",
     """            // (4) pending delete: null = dialog closed, non-null =
            // the completed item the trash button was pressed on.
            var pendingDelete by remember { mutableStateOf<DownloadEntity?>(null) }
            // The running download is the FIRST item; navigating
            // between tabs restores the saved scroll position, so
            // without this the list would re-open wherever it was last
            // left. Every time the tab (re)appears we jump to the top
            // so the active download is immediately visible.
            val listState = rememberLazyListState()
            LaunchedEffect(Unit) {
                listState.scrollToItem(0)
            }
            LazyColumn(
                modifier = Modifier.weight(1f),
                state = listState,
                contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 4.dp, bottom = 16.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
""", 1),
    ("""                items(items, key = { it.id }) { item ->
                    DownloadItemCard(
                        item = item,
                        liveBytes = liveBytes[item.id],
                        hasLog = !logs[item.id].orEmpty().isEmpty(),
                        onCancel = { viewModel.cancel(item.id) },
                        onDelete = { viewModel.delete(item.id) },
""",
     """                items(items, key = { it.id }) { item ->
                    DownloadItemCard(
                        item = item,
                        liveBytes = liveBytes[item.id],
                        hasLog = !logs[item.id].orEmpty().isEmpty(),
                        onCancel = { viewModel.cancel(item.id) },
                        onDelete = {
                            if (item.status == DownloadEntity.STATUS_COMPLETED) {
                                // Completed file on disk: ask whether the
                                // saved file should be deleted as well.
                                pendingDelete = item
                            } else {
                                viewModel.delete(item.id)
                            }
                        },
""", 1),
    ("""                        onRetry = { viewModel.retry(item.id) },
                        onOpenLog = { onOpenLog(item.id) }
                    )
                }
            }
        }
    }
}
""",
     """                        onRetry = { viewModel.retry(item.id) },
                        onOpenLog = { onOpenLog(item.id) }
                    )
                }
            }
            pendingDelete?.let { target ->
                AlertDialog(
                    onDismissRequest = { pendingDelete = null },
                    title = { Text("Delete download?") },
                    text = {
                        Text(
                            "\\"${target.title}\\" has finished.\\n" +
                                "Delete the saved file from storage too?"
                        )
                    },
                    confirmButton = {
                        TextButton(onClick = {
                            viewModel.delete(target.id, deleteFile = true)
                            pendingDelete = null
                        }) { Text("Delete file + list") }
                    },
                    dismissButton = {
                        TextButton(onClick = { pendingDelete = null }) {
                            Text("Cancel")
                        }
                        TextButton(onClick = {
                            viewModel.delete(target.id, deleteFile = false)
                            pendingDelete = null
                        }) { Text("Delete from list") }
                    }
                )
            }
        }
    }
}
""", 1),
]

patch(DS, DS_PAIRS)

# =====================================================================
# DownloadsViewModel.kt -- delete can also remove the saved file
# =====================================================================
DVM = "app/src/main/java/com/ffmux/app/ui/downloads/DownloadsViewModel.kt"

DVM_PAIRS = [
    ("""    fun delete(id: Long) {
        viewModelScope.launch(Dispatchers.IO) {
            Graph.db.downloadDao().delete(id)
        }
    }
""",
     """    fun delete(id: Long, deleteFile: Boolean = false) {
        viewModelScope.launch(Dispatchers.IO) {
            if (deleteFile) {
                // Remove the saved file from storage before dropping
                // the row. Works for both destinations (MediaStore or
                // the SAF folder): both were created by this app, so it
                // holds write access to the Uri it saved.
                val item = Graph.db.downloadDao().findById(id)
                item?.savedUri?.let { uriString ->
                    runCatching {
                        getApplication<Application>()
                            .contentResolver.delete(Uri.parse(uriString), null, null)
                    }
                }
            }
            Graph.db.downloadDao().delete(id)
        }
    }
""", 1),
    ("""import android.app.Application
import androidx.lifecycle.AndroidViewModel
""",
     """import android.app.Application
import android.net.Uri
import androidx.lifecycle.AndroidViewModel
""", 1),
]

patch(DVM, DVM_PAIRS)

# =====================================================================
# app/build.gradle.kts -- 1.4.18/25 -> 1.4.19/26
# =====================================================================
GRADLE = "app/build.gradle.kts"

GRADLE_PAIRS = [
    ("""versionCode = 25""",
     """versionCode = 26""", 1),
    ('versionName = "1.4.18"',
     'versionName = "1.4.19"', 1),
]

patch(GRADLE, GRADLE_PAIRS)

print("patched: HomeScreen.kt, DownloadsScreen.kt, DownloadsViewModel.kt, app/build.gradle.kts")
PYEOF

# ---------------------------------------------------------------------
# Post-verification: the tree must now be exactly v1.4.19.
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

verify_post "$HOME"   a7ec87da68617e164ada232aa77c90210714db0de721b08edf52589a95ee6546
verify_post "$DS"     a66c6c4cf2481745e10edfc7bc70a50ec2cd04df94801ff63a780ed763c77fb8
verify_post "$DVM"    1a91d3cff7d940444fa885aa199fe7fb2cb3a934948d1118bf9031749a984d0d
verify_post "$GRADLE" 375164bfa222472811c9c7facd436b84e26e077e3e78dafc47a8acc75acecb7f

echo "Post-patch hashes verified."
echo ""
echo "Patch 26 applied: v1.4.19 (versionCode 26)"
echo "  1. Author row: Author first (left), Ext second (right)"
echo "  2. on fetch error: red reset button under the big blue button"
echo "  3. Downloads tab always opens at the top of the list"
echo "  4. trash on completed item asks: delete list only / file + list"
