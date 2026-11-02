package com.ffmux.app.ui.downloads

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.widget.Toast
import androidx.compose.foundation.background
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.view.WindowCompat
import com.ffmux.app.Graph

/** Terminal look of the log: always dark, green monospace text. */
private val LogBackground = Color(0xFF0A0F0A)
private val LogTextGreen = Color(0xFF4AF626)
private val LogDimGreen = Color(0xFF8FBF9F)
private val LogHeaderText = Color(0xFFD8F3D8)

/**
 * Full terminal log of one download: every yt-dlp output line, live.
 * The screen is drawn edge to edge with its own dark background, so it
 * insets itself below the status bar and above the navigation bar, and
 * switches the system bar icons to light while it is open. Any line can
 * be long-pressed for text selection and the header button copies the
 * whole log to the clipboard.
 */
@Composable
fun LogScreen(
    downloadId: Long,
    onBack: () -> Unit
) {
    val logs by Graph.downloadLogs.collectAsState()
    val lines = logs[downloadId].orEmpty()
    val clipboard = LocalClipboardManager.current
    val context = LocalContext.current
    val listState = rememberLazyListState()
    var title by remember { mutableStateOf("") }

    // The log is always dark: force light system bar icons while it is
    // visible, restore the theme icons when it goes away.
    val view = LocalView.current
    val systemDark = isSystemInDarkTheme()
    DisposableEffect(systemDark) {
        val window = view.context.findActivity()?.window
        val controller = window?.let { WindowCompat.getInsetsController(it, view) }
        controller?.isAppearanceLightStatusBars = false
        controller?.isAppearanceLightNavigationBars = false
        onDispose {
            controller?.isAppearanceLightStatusBars = !systemDark
            controller?.isAppearanceLightNavigationBars = !systemDark
        }
    }

    LaunchedEffect(downloadId) {
        title = Graph.db.downloadDao().findById(downloadId)?.title.orEmpty()
    }
    LaunchedEffect(lines.size) {
        if (lines.isNotEmpty()) listState.animateScrollToItem(lines.size - 1)
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(LogBackground)
            .statusBarsPadding()
            .navigationBarsPadding()
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .height(56.dp)
                .padding(start = 8.dp, end = 8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            IconButton(onClick = onBack) {
                Icon(
                    Icons.AutoMirrored.Filled.ArrowBack,
                    contentDescription = "Back",
                    tint = LogHeaderText
                )
            }
            Text(
                text = "Terminal log",
                style = MaterialTheme.typography.titleLarge,
                color = LogHeaderText,
                maxLines = 1
            )
            Spacer(modifier = Modifier.weight(1f))
            IconButton(
                onClick = {
                    clipboard.setText(AnnotatedString(lines.joinToString("\n")))
                    Toast.makeText(context, "Log copied to clipboard", Toast.LENGTH_SHORT).show()
                },
                enabled = lines.isNotEmpty()
            ) {
                Icon(
                    Icons.Outlined.ContentCopy,
                    contentDescription = "Copy log",
                    tint = LogHeaderText
                )
            }
        }
        if (title.isNotBlank()) {
            Text(
                text = title,
                style = MaterialTheme.typography.bodySmall,
                color = LogDimGreen,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.padding(horizontal = 16.dp)
            )
        }

        if (lines.isEmpty()) {
            Box(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth(),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    "No terminal output for this download yet.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = LogDimGreen,
                    textAlign = TextAlign.Center
                )
            }
        } else {
            SelectionContainer {
                LazyColumn(
                    state = listState,
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxWidth(),
                    contentPadding = PaddingValues(
                        start = 16.dp, end = 16.dp, top = 10.dp, bottom = 16.dp
                    ),
                    verticalArrangement = Arrangement.spacedBy(1.dp)
                ) {
                    itemsIndexed(lines) { _, line ->
                        Text(
                            text = line,
                            fontFamily = FontFamily.Monospace,
                            fontSize = 11.sp,
                            lineHeight = 15.sp,
                            color = LogTextGreen,
                            modifier = Modifier.padding(vertical = 1.dp)
                        )
                    }
                }
            }
        }
    }
}

private tailrec fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findActivity()
    else -> null
}
