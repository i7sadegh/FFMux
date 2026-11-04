package com.ffmux.app.ui.home

import android.app.Application
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.ffmux.app.Graph
import com.ffmux.app.data.db.DownloadEntity
import com.ffmux.app.engine.DownloadService
import com.ffmux.app.engine.FormatSections
import com.ffmux.app.engine.VideoInfo
import com.ffmux.app.engine.YtDlpEngine
import kotlinx.coroutines.launch

sealed interface HomeUiState {
    data object Idle : HomeUiState
    data object Loading : HomeUiState
    data class Error(val message: String) : HomeUiState
    data class Info(
        val fetchedUrl: String,
        val info: VideoInfo,
        val sections: FormatSections
    ) : HomeUiState
}

/**
 * Home screen state holder. The URL, the fetched video info and the
 * quality selections SURVIVE starting a download and switching tabs:
 * nothing is reset when a download is queued, so coming back from the
 * Downloads tab shows the same video and picks again. The square
 * button left of the Download bar calls resetScreen() to wipe all of
 * it on demand and return to the empty start page.
 */
class HomeViewModel(application: Application) : AndroidViewModel(application) {

    var url by mutableStateOf("")
        private set
    var state by mutableStateOf<HomeUiState>(HomeUiState.Idle)
        private set

    /**
     * Bumped by every fetch() and by resetScreen(). A fetch only
     * stores its result while the generation still matches, so the
     * info of a link the user already cleared never pops back in.
     */
    private var fetchGeneration = 0

    /** True while the "Best" shortcut card is the active selection. */
    var bestSelected by mutableStateOf(true)
        private set

    /** Index into HomeUiState.Info.sections.video, -1 = none. */
    var selectedVideo by mutableStateOf(-1)
        private set

    /** Index into HomeUiState.Info.sections.audio, -1 = none. */
    var selectedAudio by mutableStateOf(-1)
        private set

    var editableTitle by mutableStateOf("")
        private set
    var editableUploader by mutableStateOf("")
        private set

    /** yt-dlp extras picked under the quality cards (ytdlnis style). */
    var embedThumbnail by mutableStateOf(false)
        private set

    /**
     * Metadata is wanted for essentially every download, so the chip
     * is ON by default and every newly fetched link starts from that
     * default again. It can still be turned off for a clean file.
     */
    var embedMetadata by mutableStateOf(true)
        private set
    var splitChapters by mutableStateOf(false)
        private set

    /** Download straight to the final name, no .part files (--no-part). */
    var noPart by mutableStateOf(false)
        private set

    /** Recording time limit in minutes, 0 = unlimited (live streams). */
    var recordMinutes by mutableStateOf(0)
        private set

    /** Extra yt-dlp arguments from the "Extra commands" dialog. */
    var extraArgs by mutableStateOf("")
        private set

    /** Selected subtitle languages (yt-dlp codes), empty = no subtitles. */
    var subLangs by mutableStateOf(setOf<String>())
        private set

    fun updateTitle(value: String) {
        editableTitle = value
    }

    fun updateUploader(value: String) {
        editableUploader = value
    }

    init {
        viewModelScope.launch {
            Graph.pendingUrl.collect { shared ->
                if (!shared.isNullOrBlank()) {
                    url = shared
                    Graph.pendingUrl.value = null
                    fetch()
                }
            }
        }
    }

    fun updateUrl(value: String) {
        url = value
    }

    /**
     * Wipes the fetched link, video info, formats, selections and the
     * per-link recording limit and returns to the empty start page
     * with the big circular button. The option chips keep their
     * values: they are user preferences, not per-link state. A fetch
     * that is still running is dropped by its generation; downloads
     * already sitting in the queue are NOT touched.
     */
    fun resetScreen() {
        fetchGeneration++
        url = ""
        state = HomeUiState.Idle
        bestSelected = true
        selectedVideo = -1
        selectedAudio = -1
        editableTitle = ""
        editableUploader = ""
        recordMinutes = 0
    }

    fun toggleEmbedThumbnail() {
        embedThumbnail = !embedThumbnail
    }

    fun toggleEmbedMetadata() {
        embedMetadata = !embedMetadata
    }

    fun toggleSplitChapters() {
        splitChapters = !splitChapters
    }

    fun toggleNoPart() {
        noPart = !noPart
    }

    fun updateRecordMinutes(value: Int) {
        recordMinutes = value.coerceIn(0, 1440)
    }

    fun updateExtraArgs(value: String) {
        extraArgs = value
    }

    fun updateSubLangs(langs: Set<String>) {
        subLangs = langs
    }

    /**
     * Extra yt-dlp arguments for the option chips only, as one space
     * separated "--flag value" string. Used by the command preview.
     */
    fun baseDownloadArgs(): String {
        val args = mutableListOf<String>()
        if (embedThumbnail) {
            args.add("--embed-thumbnail")
            args.add("--convert-thumbnails")
            args.add("jpg")
        }
        if (subLangs.isNotEmpty()) {
            args.add("--embed-subs")
            args.add("--sub-langs")
            args.add(subLangs.sorted().joinToString(","))
        }
        if (embedMetadata) args.add("--embed-metadata")
        if (splitChapters) args.add("--split-chapters")
        if (noPart) args.add("--no-part")
        return args.joinToString(" ")
    }

    /**
     * Everything the engine receives: the option chips plus the extra
     * arguments from the "Extra commands" dialog. Parsed back by the
     * engine right before the download runs, so the chosen flags travel
     * inside the queue entity and survive app restarts.
     */
    fun buildDownloadArgs(): String {
        val base = baseDownloadArgs()
        val extra = extraArgs
            .replace(Regex("[\\r\\n\\t]+"), " ")
            .trim()
            .split(Regex("\\s+"))
            .filter { it.isNotBlank() }
        val parts = mutableListOf<String>()
        if (base.isNotBlank()) parts.add(base)
        parts.addAll(extra)
        return parts.joinToString(" ")
    }

    fun selectBest() {
        bestSelected = true
        selectedVideo = -1
        selectedAudio = -1
    }

    fun toggleVideo(index: Int) {
        bestSelected = false
        selectedVideo = if (selectedVideo == index) -1 else index
    }

    fun toggleAudio(index: Int) {
        bestSelected = false
        selectedAudio = if (selectedAudio == index) -1 else index
    }

    fun fetch() {
        val target = url.trim()
        if (target.isBlank()) return
        val generation = ++fetchGeneration
        state = HomeUiState.Loading
        viewModelScope.launch {
            try {
                Graph.awaitEngine()
                val info = Graph.engine.fetchInfo(target)
                if (info.type == "playlist") {
                    if (generation == fetchGeneration) {
                        state = HomeUiState.Error("Playlist links are not supported yet.")
                    }
                    return@launch
                }
                val sections = YtDlpEngine.buildFormatSections(info)
                if (sections.video.isEmpty() && sections.audio.isEmpty()) {
                    if (generation == fetchGeneration) {
                        state = HomeUiState.Error("No downloadable formats found.")
                    }
                    return@launch
                }
                if (generation != fetchGeneration) return@launch
                bestSelected = true
                selectedVideo = -1
                selectedAudio = -1
                editableTitle = info.title ?: "Untitled"
                editableUploader = info.uploader ?: ""
                // Every new link starts from the default: metadata on.
                embedMetadata = true
                state = HomeUiState.Info(fetchedUrl = target, info = info, sections = sections)
            } catch (e: Exception) {
                if (generation == fetchGeneration) {
                    state = HomeUiState.Error((e.message ?: "Could not fetch video info.").take(300))
                }
            }
        }
    }

    /** The yt-dlp format selector for the current selection, or null. */
    fun selectedSelector(): String? {
        val current = state as? HomeUiState.Info ?: return null
        val video = current.sections.video.getOrNull(selectedVideo)
        val audio = current.sections.audio.getOrNull(selectedAudio)
        return when {
            bestSelected -> current.sections.best.selector
            video != null && audio != null -> "${video.selector}+${audio.selector}"
            video != null -> video.selector
            audio != null -> audio.selector
            else -> null
        }
    }

    /** True when a video-only stream is picked without any audio stream. */
    fun isVideoOnlySelection(): Boolean {
        if (bestSelected) return false
        val current = state as? HomeUiState.Info ?: return false
        return selectedVideo >= 0 && selectedAudio < 0 && current.sections.video.isNotEmpty()
    }

    /** Short label of the current selection, shown in the Downloads list. */
    fun selectedLabel(): String {
        val current = state as? HomeUiState.Info ?: return ""
        val video = current.sections.video.getOrNull(selectedVideo)
        val audio = current.sections.audio.getOrNull(selectedAudio)
        return when {
            bestSelected -> "Best"
            video != null && audio != null -> "${video.label} + ${audio.label}"
            video != null -> "${video.label} (video only)"
            audio != null -> audio.label
            else -> ""
        }
    }

    /** Estimated byte size of the resulting file, or null when unknown. */
    fun selectedSizeBytes(): Long? {
        val current = state as? HomeUiState.Info ?: return null
        val video = current.sections.video.getOrNull(selectedVideo)
        val audio = current.sections.audio.getOrNull(selectedAudio)
        return when {
            bestSelected -> current.sections.best.sizeBytes
            video != null && audio != null ->
                if (video.sizeBytes != null && audio.sizeBytes != null) {
                    video.sizeBytes!! + audio.sizeBytes!!
                } else {
                    video.sizeBytes ?: audio.sizeBytes
                }
            video != null -> video.sizeBytes
            audio != null -> audio.sizeBytes
            else -> null
        }
    }

    fun startDownload(onQueued: () -> Unit) {
        val current = state as? HomeUiState.Info ?: return
        val selector = selectedSelector() ?: return
        val info = current.info
        // The link that was actually FETCHED, not the live text field:
        // clearing or editing the field after fetching must not break
        // (or silently retarget) the download.
        val target = current.fetchedUrl
        val label = selectedLabel().ifBlank { "Best" }

        viewModelScope.launch {
            val entity = DownloadEntity(
                url = target,
                title = editableTitle.ifBlank { info.title ?: "Untitled" },
                thumbnail = info.thumbnail,
                uploader = editableUploader.ifBlank { info.uploader },
                durationSec = info.duration,
                formatSelector = selector,
                formatLabel = label,
                downloadArgs = buildDownloadArgs(),
                recordMinutes = recordMinutes,
                createdAt = System.currentTimeMillis()
            )
            Graph.db.downloadDao().insert(entity)
            DownloadService.start(getApplication())
            // Intentionally NOT clearing url / state / selections here:
            // the user asked for the previous link and formats to stay.
            onQueued()
        }
    }
}
