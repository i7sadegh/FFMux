package com.ffmux.app.engine

import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Environment
import android.provider.MediaStore
import androidx.documentfile.provider.DocumentFile
import com.ffmux.app.util.MimeUtils
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

/**
 * Moves a finished download from the private cache directory into
 * user-visible storage: either the SAF folder the user picked, or
 * the MediaStore Downloads collection by default.
 */
object FileSaver {

    suspend fun save(context: Context, treeUri: String?, file: File): Uri? =
        withContext(Dispatchers.IO) {
            val displayName = file.name
            val mime = MimeUtils.fromFileName(displayName)

            if (treeUri != null) {
                saveToSafTree(context, treeUri, file, displayName, mime)
            } else {
                saveToMediaStore(context, file, displayName, mime)
            }
        }

    private fun saveToSafTree(
        context: Context,
        treeUri: String,
        file: File,
        displayName: String,
        mime: String
    ): Uri? {
        val tree = DocumentFile.fromTreeUri(context, Uri.parse(treeUri)) ?: return null
        val target = tree.createFile(mime, displayName) ?: return null
        context.contentResolver.openOutputStream(target.uri)?.use { out ->
            file.inputStream().use { input -> input.copyTo(out) }
        }
        return target.uri
    }

    private fun saveToMediaStore(
        context: Context,
        file: File,
        displayName: String,
        mime: String
    ): Uri? {
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, displayName)
            put(MediaStore.MediaColumns.MIME_TYPE, mime)
            put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/FFMux")
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = context.contentResolver
            .insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values) ?: return null

        val copied = runCatching {
            context.contentResolver.openOutputStream(uri)?.use { out ->
                file.inputStream().use { input -> input.copyTo(out) }
            }
        }.isSuccess

        return if (copied) {
            values.clear()
            values.put(MediaStore.MediaColumns.IS_PENDING, 0)
            runCatching { context.contentResolver.update(uri, values, null, null) }
            uri
        } else {
            runCatching { context.contentResolver.delete(uri, null, null) }
            null
        }
    }
}
