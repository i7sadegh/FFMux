package com.ffmux.app.data

import android.content.Context
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

private val Context.dataStore by preferencesDataStore(name = "settings")

class SettingsStore(private val context: Context) {

    private val treeUriKey = stringPreferencesKey("download_tree_uri")

    /** SAF tree uri of the user-chosen download folder, or null for the default. */
    val treeUri: Flow<String?> = context.dataStore.data.map { prefs -> prefs[treeUriKey] }

    suspend fun setTreeUri(uri: String?) {
        context.dataStore.edit { prefs ->
            if (uri == null) prefs.remove(treeUriKey) else prefs[treeUriKey] = uri
        }
    }
}
