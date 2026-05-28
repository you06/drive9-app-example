package com.drive9.example

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaPlayer
import android.media.MediaRecorder
import android.os.Bundle
import android.speech.RecognizerIntent
import android.text.Editable
import android.text.InputType
import android.text.TextWatcher
import android.view.View
import android.view.ViewGroup
import android.widget.AdapterView
import android.widget.ArrayAdapter
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.ScrollView
import android.widget.Spinner
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
private const val MIN_RECORDING_BYTES = 1024L

private data class SearchLanguageOption(val displayName: String, val localeTag: String)

private val SEARCH_LANGUAGES = listOf(
    SearchLanguageOption("中文", "zh-CN"),
    SearchLanguageOption("English", "en-US"),
    SearchLanguageOption("日本語", "ja-JP"),
)

class MainActivity : ComponentActivity() {
    private val model: Drive9ExampleViewModel by viewModels()

    private lateinit var baseUrlInput: EditText
    private lateinit var apiKeyInput: EditText
    private lateinit var statusText: TextView
    private lateinit var progress: ProgressBar
    private var searchTranscriptInput: EditText? = null
    private var recorder: MediaRecorder? = null
    private var player: MediaPlayer? = null

    private val requestRecordPermission =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            if (granted) {
                startUploadRecordingNow()
                showMainScreen()
            } else {
                status("Microphone permission is required")
            }
        }

    private val speechRecognizerLauncher =
        registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
            if (result.resultCode != RESULT_OK) {
                status("Speech recognition cancelled.")
                return@registerForActivityResult
            }
            val text = result.data
                ?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)
                ?.firstOrNull()
                ?.trim()
                .orEmpty()
            if (text.isEmpty()) {
                status("Could not transcribe the recording. Try again.")
                return@registerForActivityResult
            }
            model.searchTranscript = text
            searchTranscriptInput?.setText(text)
            searchTranscriptInput?.setSelection(text.length)
            status("Heard: $text")
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
        val recording = model.isRecordingUpload

        if (recording) {
            root.addView(label("Recording"))
            root.addView(TextView(this).apply {
                text = "Recording upload audio... tap Stop to finish."
                setTextColor(0xffb00020.toInt())
            })
        }

        root.addView(label("Upload Recording"))
        root.addView(TextView(this).apply {
            text = model.uploadRecording?.name ?: "No upload recording yet"
            tag = "upload-name"
        })
        root.addView(button(if (model.isRecordingUpload) "Stop Upload Recording" else "Record Upload Audio") {
            toggleUploadRecording()
        }.apply {
            tag = "upload-record-button"
        })
        root.addView(button("Upload Saved Recording") { uploadRecording() }.apply {
            isEnabled = model.uploadRecording != null && !model.isRecordingUpload
        })

        root.addView(label("Search"))

        val languageSpinner = Spinner(this).apply {
            adapter = ArrayAdapter(
                this@MainActivity,
                android.R.layout.simple_spinner_dropdown_item,
                SEARCH_LANGUAGES.map { it.displayName },
            )
            val currentIndex = SEARCH_LANGUAGES.indexOfFirst { it.localeTag == model.searchLanguage }
                .takeIf { it >= 0 } ?: 0
            setSelection(currentIndex)
            onItemSelectedListener = object : AdapterView.OnItemSelectedListener {
                override fun onItemSelected(parent: AdapterView<*>?, view: View?, position: Int, id: Long) {
                    model.searchLanguage = SEARCH_LANGUAGES[position].localeTag
                }

                override fun onNothingSelected(parent: AdapterView<*>?) {}
            }
        }
        root.addView(languageSpinner)

        root.addView(button("Speak Search Query") { launchSpeechRecognizer() }.apply {
            isEnabled = !model.isRecordingUpload
        })

        val transcriptInput = EditText(this).apply {
            hint = "Search query (edit if needed)"
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE
            setText(model.searchTranscript)
            addTextChangedListener(object : TextWatcher {
                override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
                override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {}
                override fun afterTextChanged(s: Editable?) {
                    model.searchTranscript = s?.toString().orEmpty()
                }
            })
        }
        searchTranscriptInput = transcriptInput
        root.addView(transcriptInput)

        root.addView(button("Search Recordings") { searchByTranscript() }.apply {
            isEnabled = !model.isRecordingUpload && model.searchTranscript.trim().isNotEmpty()
        })

        root.addView(progress)
        root.addView(statusText)
        setContentView(ScrollView(this).apply { addView(root) })
        if (recording) {
            status("Recording upload audio... tap Stop to finish.")
        } else {
            status("Ready. Record audio to upload, or speak a query to search $AUDIO_PREFIX.")
        }
    }

    private fun toggleUploadRecording() {
        if (model.isRecordingUpload) {
            stopUploadRecording()
            showMainScreen()
            return
        }
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
            startUploadRecordingNow()
            showMainScreen()
        } else {
            requestRecordPermission.launch(Manifest.permission.RECORD_AUDIO)
        }
    }

    private fun startUploadRecordingNow() {
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
        model.uploadRecording = file
        model.isRecordingUpload = true
        status("Recording upload audio...")
    }

    private fun stopUploadRecording() {
        runCatching { recorder?.stop() }
        recorder?.release()
        recorder = null
        model.isRecordingUpload = false
        val file = model.uploadRecording
        if (file != null && file.length() < MIN_RECORDING_BYTES) {
            status("Upload recording is only ${file.length()} bytes. Record for a few seconds and try again.")
        } else {
            status("Upload recording ready${file?.let { " (${it.length()} bytes)" } ?: ""}")
        }
    }

    private fun launchSpeechRecognizer() {
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, model.searchLanguage)
            putExtra(RecognizerIntent.EXTRA_PROMPT, "Speak your search query")
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
        }
        try {
            speechRecognizerLauncher.launch(intent)
        } catch (_: ActivityNotFoundException) {
            status("No speech recognizer is installed on this device.")
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
            status("Uploading saved recording to $AUDIO_PREFIX/${file.name}...")
            client().uploadFile(file.absolutePath, "$AUDIO_PREFIX/${file.name}")
            status("Uploaded ${file.name} to $AUDIO_PREFIX")
        }
    }

    private fun searchByTranscript() {
        val query = (searchTranscriptInput?.text?.toString() ?: model.searchTranscript).trim()
        if (query.isEmpty()) {
            status("Search transcript is empty. Speak or type a query first.")
            return
        }
        model.searchTranscript = query
        launchDrive9 {
            status("Searching $AUDIO_PREFIX for \"$query\"...")
            val hits = client().grep(query, AUDIO_PREFIX, 20)
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
            showResultsScreen(enriched, query)
        }
    }

    private fun showResultsScreen(results: List<AudioResult>, query: String) {
        val root = verticalRoot()
        statusText = TextView(this)
        progress = ProgressBar(this).apply { visibility = View.GONE }

        root.addView(label("Search Results"))
        root.addView(TextView(this).apply {
            text = "Query: \"$query\""
            setPadding(0, 0, 0, 8)
        })
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
        status("Found ${results.size} recording${if (results.size == 1) "" else "s"} for \"$query\"")
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
    var isRecordingUpload: Boolean = false
    var searchLanguage: String = SEARCH_LANGUAGES.first().localeTag
    var searchTranscript: String = ""
}
