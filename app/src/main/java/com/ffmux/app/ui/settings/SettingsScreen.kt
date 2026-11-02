package com.ffmux.app.ui.settings

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel

@Composable
fun SettingsScreen(viewModel: SettingsViewModel = viewModel()) {
    val treeUri by viewModel.treeUri.collectAsStateWithLifecycle()

    val folderPicker = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocumentTree()
    ) { uri ->
        if (uri != null) viewModel.chooseFolder(uri)
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text("Settings", style = MaterialTheme.typography.headlineMedium)

        Card(modifier = Modifier.fillMaxWidth()) {
            Column(
                modifier = Modifier.padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Text("Storage", style = MaterialTheme.typography.titleMedium)
                Text("Download folder", style = MaterialTheme.typography.bodyLarge)
                Text(
                    folderLabel(treeUri),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    TextButton(onClick = { folderPicker.launch(null) }) {
                        Text("Choose folder")
                    }
                    if (treeUri != null) {
                        TextButton(onClick = { viewModel.resetFolder() }) {
                            Text("Use default")
                        }
                    }
                }
                Text(
                    "By default files are saved to Downloads/FFMux.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }

        Card(modifier = Modifier.fillMaxWidth()) {
            Column(
                modifier = Modifier.padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Text("yt-dlp engine", style = MaterialTheme.typography.titleMedium)
                Text(
                    "Current version: ${viewModel.engineVersion ?: "loading…"}",
                    style = MaterialTheme.typography.bodyMedium
                )
                Button(
                    onClick = { viewModel.checkForUpdate() },
                    enabled = !viewModel.updating,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    if (viewModel.updating) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(18.dp),
                            strokeWidth = 2.dp
                        )
                        Spacer(Modifier.width(8.dp))
                        Text("Updating…")
                    } else {
                        Text("Check for updates")
                    }
                }
                viewModel.updateMessage?.let {
                    Text(
                        it,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.primary
                    )
                }
            }
        }
    }
}

private fun folderLabel(treeUri: String?): String {
    if (treeUri == null) return "Default (Downloads/FFMux)"
    return runCatching {
        val uri = Uri.parse(treeUri)
        val segment = uri.lastPathSegment ?: return "Custom folder"
        val name = segment.substringAfterLast(':').substringAfterLast('/')
        if (name.isBlank()) "Custom folder" else name
    }.getOrDefault("Custom folder")
}
