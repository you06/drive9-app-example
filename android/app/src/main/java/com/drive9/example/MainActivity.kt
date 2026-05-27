package com.drive9.example

import android.Manifest
import android.content.pm.PackageManager
import android.media.MediaPlayer
import android.media.MediaRecorder
import android.os.Bundle
import android.text.InputType
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.ScrollView
import android.widget.TextView
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.core.content.ContextCompat
import androidx.lifecycle.ViewModel
import androidx.lifecycle.lifecycleScope
import com.drive9.mobile.Drive9Client
import java.io.File
import kotlinx.coroutines.launch

private const val DEFAULT_SERVER = "https://api.drive9.ai"
private const val AUDIO_PREFIX = "/mobile-demo/audio"
private const val QUERY_TMP_PREFIX = "/mobile-demo/tmp-query"
private const val MIN_RECORDING_BYTES = 1024L

class MainActivity : ComponentActivity() {
    private val model: Drive9ExampleViewModel by viewModels()

    private lateinit var baseUrlInput: EditText
    private lateinit var apiKeyInput: EditText
    private lateinit var statusText: TextView
    private lateinit var progress: ProgressBar
    private var recorder: MediaRecorder? = null
    private var player: MediaPlayer? = null
    private var pendingRecording: RecordingPurpose? = null

    private val requestRecordPermission =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            val purpose = pendingRecording
            pendingRecording = null
            if (granted && purpose != null) {
                startRecordingNow(purpose)
                showMainScreen()
            } else {
                status("Microphone permission is required")
            }
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        showConnectionScreen()
    }

    override fun onDestroy() {
        recorder?.release()
        player?.release()
        super.onDestroy()
    }

    private fun showConnectionScreen() {
        val root = verticalRoot()
        baseUrlInput = input("Drive9 server", DEFAULT_SERVER)
        apiKeyInput = input("Drive9 API key", "").apply {
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD
        }
        statusText = TextView(this)
        progress = ProgressBar(this).apply { visibility = View.GONE }

        root.addView(label("Drive9"))
        root.addView(baseUrlInput)
        root.addView(apiKeyInput)
        root.addView(button("Continue") {
            if (apiKeyInput.text.toString().trim().isEmpty()) {
                status("Drive9 API key is required")
            } else {
                model.baseUrl = baseUrlInput.text.toString().trim()
                model.apiKey = apiKeyInput.text.toString().trim()
                showMainScreen()
            }
        })
        root.addView(progress)
        root.addView(statusText)
        setContentView(ScrollView(this).apply { addView(root) })
        status("Enter an existing Drive9 API key.")
    }

    private fun showMainScreen() {
        val root = verticalRoot()
        statusText = TextView(this)
        progress = ProgressBar(this).apply { visibility = View.GONE }
        val recording = model.recordingPurpose

        if (recording != null) {
            root.addView(label("Recording"))
            root.addView(TextView(this).apply {
                text = "Recording ${recording.label}... tap Stop to finish."
                setTextColor(0xffb00020.toInt())
            })
        }

        root.addView(label("Upload Recording"))
        root.addView(TextView(this).apply {
            text = model.uploadRecording?.name ?: "No upload recording yet"
            tag = "upload-name"
        })
        root.addView(button(if (model.recordingPurpose == RecordingPurpose.Upload) "Stop Upload Recording" else "Record Upload") { toggleRecording(RecordingPurpose.Upload) }.apply {
            isEnabled = model.recordingPurpose != RecordingPurpose.Search
            tag = "upload-record-button"
        })
        root.addView(button("Upload Recording") { uploadRecording() }.apply {
            isEnabled = model.uploadRecording != null && model.recordingPurpose == null
        })

        root.addView(label("Search Recording"))
        root.addView(TextView(this).apply {
            text = model.searchRecording?.name ?: "No search recording yet"
            tag = "search-name"
        })
        root.addView(button(if (model.recordingPurpose == RecordingPurpose.Search) "Stop Search Recording" else "Record Search Query") { toggleRecording(RecordingPurpose.Search) }.apply {
            isEnabled = model.recordingPurpose != RecordingPurpose.Upload
            tag = "search-record-button"
        })
        root.addView(button("Search Recordings") { searchRecording() }.apply {
            isEnabled = model.searchRecording != null && model.recordingPurpose == null
        })

        root.addView(progress)
        root.addView(statusText)
        setContentView(ScrollView(this).apply { addView(root) })
        if (recording == null) {
            status("Ready. Record audio to upload or search in $AUDIO_PREFIX.")
        } else {
            status("Recording ${recording.label}... tap Stop to finish.")
        }
    }

    private fun toggleRecording(purpose: RecordingPurpose) {
        if (model.recordingPurpose == purpose) {
            stopRecording()
            showMainScreen()
            return
        }
        if (model.recordingPurpose != null) {
            status("Stop the current recording first")
            return
        }
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
            startRecordingNow(purpose)
            showMainScreen()
        } else {
            pendingRecording = purpose
            requestRecordPermission.launch(Manifest.permission.RECORD_AUDIO)
        }
    }

    private fun startRecordingNow(purpose: RecordingPurpose) {
        val file = File(cacheDir, "recording-${System.currentTimeMillis()}.m4a")
        val mediaRecorder = MediaRecorder()
        mediaRecorder.setAudioSource(MediaRecorder.AudioSource.MIC)
        mediaRecorder.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
        mediaRecorder.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
        mediaRecorder.setAudioSamplingRate(44_100)
        mediaRecorder.setAudioChannels(1)
        mediaRecorder.setOutputFile(file.absolutePath)
        mediaRecorder.prepare()
        mediaRecorder.start()
        recorder = mediaRecorder
        model.recordingPurpose = purpose
        when (purpose) {
            RecordingPurpose.Upload -> model.uploadRecording = file
            RecordingPurpose.Search -> model.searchRecording = file
        }
        status("Recording ${purpose.label}...")
    }

    private fun stopRecording() {
        runCatching { recorder?.stop() }
        recorder?.release()
        recorder = null
        val purpose = model.recordingPurpose
        model.recordingPurpose = null
        val file = when (purpose) {
            RecordingPurpose.Upload -> model.uploadRecording
            RecordingPurpose.Search -> model.searchRecording
            null -> null
        }
        if (file != null && file.length() < MIN_RECORDING_BYTES) {
            status("${purpose.label} is only ${file.length()} bytes. Record for a few seconds and try again.")
        } else {
            status("${purpose?.label ?: "Recording"} ready${file?.let { " (${it.length()} bytes)" } ?: ""}")
        }
    }

    private fun uploadRecording() {
        val file = model.uploadRecording
        if (file == null) {
            status("Record upload audio first")
            return
        }
        if (!validateRecordingFile(file)) return
        launchDrive9 {
            client().uploadFile(file.absolutePath, "$AUDIO_PREFIX/${file.name}")
            status("Uploaded ${file.name} to $AUDIO_PREFIX")
        }
    }

    private fun searchRecording() {
        val file = model.searchRecording
        if (file == null) {
            status("Record a search query first")
            return
        }
        if (!validateRecordingFile(file)) return
        launchDrive9 {
            val hits = client().searchByFile(
                localPath = file.absolutePath,
                tmpPrefix = QUERY_TMP_PREFIX,
                searchPrefix = AUDIO_PREFIX,
                limit = 20,
            )
            val enriched = hits.map { hit ->
                val meta = runCatching { client().statMetadata(hit.path) }.getOrNull()
                AudioResult(
                    path = hit.path,
                    name = hit.name,
                    sizeBytes = hit.sizeBytes,
                    score = hit.score,
                    semanticText = meta?.semanticText?.trim().orEmpty(),
                )
            }
            showResultsScreen(enriched)
        }
    }

    private fun showResultsScreen(results: List<AudioResult>) {
        val root = verticalRoot()
        statusText = TextView(this)
        progress = ProgressBar(this).apply { visibility = View.GONE }

        root.addView(label("Search Results"))
        if (results.isEmpty()) {
            root.addView(TextView(this).apply { text = "No recordings found." })
        }
        results.forEach { result ->
            root.addView(TextView(this).apply {
                text = buildString {
                    append(result.name.ifBlank { result.path })
                    append("\n")
                    append(result.semanticText.ifBlank { "No semantic summary is available." })
                    append("\n")
                    append(result.sizeBytes)
                    append(" bytes")
                    if (result.score != null) append(" · score ${"%.4f".format(result.score)}")
                }
                setPadding(0, 16, 0, 8)
            })
            root.addView(button("Play Audio") { play(result) })
        }
        root.addView(button("Back") { showMainScreen() })
        root.addView(progress)
        root.addView(statusText)
        setContentView(ScrollView(this).apply { addView(root) })
        status("Found ${results.size} recording${if (results.size == 1) "" else "s"}")
    }

    private fun play(result: AudioResult) {
        launchDrive9 {
            val local = File(cacheDir, "drive9-play-${System.nanoTime()}-${result.name.ifBlank { "audio.m4a" }}")
            client().downloadFile(result.path, local.absolutePath)
            player?.release()
            player = MediaPlayer().apply {
                setDataSource(local.absolutePath)
                setOnCompletionListener {
                    it.release()
                    if (player === it) player = null
                }
                prepare()
                start()
            }
            status("Playing ${result.name.ifBlank { result.path }}")
        }
    }

    private fun validateRecordingFile(file: File): Boolean {
        val size = file.length()
        if (size < MIN_RECORDING_BYTES) {
            status("Recording file is only $size bytes. Record for a few seconds and try again.")
            return false
        }
        return true
    }

    private fun launchDrive9(block: suspend () -> Unit) {
        progress.visibility = View.VISIBLE
        lifecycleScope.launch {
            try {
                block()
            } catch (e: Throwable) {
                status(e.message ?: e.toString())
            } finally {
                progress.visibility = View.GONE
            }
        }
    }

    private fun client(): Drive9Client =
        Drive9Client(baseUrl = model.baseUrl, apiKey = model.apiKey)

    private fun verticalRoot(): LinearLayout =
        LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(32, 32, 32, 32)
        }

    private fun input(hint: String, value: String): EditText =
        EditText(this).apply {
            this.hint = hint
            setText(value)
            setSingleLine(true)
        }

    private fun label(text: String): TextView =
        TextView(this).apply {
            this.text = text
            textSize = 18f
            setPadding(0, 24, 0, 8)
        }

    private fun button(text: String, action: () -> Unit): Button =
        Button(this).apply {
            this.text = text
            setOnClickListener { action() }
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            )
        }

    private fun status(message: String) {
        statusText.text = message
    }
}

enum class RecordingPurpose(val label: String) {
    Upload("upload audio"),
    Search("search query"),
}

private data class AudioResult(
    val path: String,
    val name: String,
    val sizeBytes: Long,
    val score: Double?,
    val semanticText: String,
)

class Drive9ExampleViewModel : ViewModel() {
    var baseUrl: String = DEFAULT_SERVER
    var apiKey: String = ""
    var uploadRecording: File? = null
    var searchRecording: File? = null
    var recordingPurpose: RecordingPurpose? = null
}
