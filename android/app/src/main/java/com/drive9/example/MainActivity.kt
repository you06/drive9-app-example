package com.drive9.example

import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
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
import androidx.lifecycle.ViewModel
import androidx.lifecycle.lifecycleScope
import com.drive9.mobile.Drive9Client
import com.drive9.mobile.Drive9SearchResult
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class MainActivity : ComponentActivity() {
    private val model: Drive9ExampleViewModel by viewModels()

    private lateinit var baseUrlInput: EditText
    private lateinit var apiKeyInput: EditText
    private lateinit var remotePathInput: EditText
    private lateinit var searchPrefixInput: EditText
    private lateinit var queryInput: EditText
    private lateinit var statusText: TextView
    private lateinit var resultsText: TextView
    private lateinit var progress: ProgressBar

    private val filePicker = registerForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) {
            contentResolver.takePersistableUriPermission(uri, android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION)
            model.selectedUri = uri
            val name = displayName(uri)
            status("Selected $name")
            if (remotePathInput.text.toString() == "/mobile-demo/example.txt") {
                remotePathInput.setText("/mobile-demo/$name")
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        buildUi()
    }

    private fun buildUi() {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(32, 32, 32, 32)
        }

        baseUrlInput = input("Base URL", "https://")
        apiKeyInput = input("Drive9 API key", "").apply {
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD
        }
        remotePathInput = input("Remote upload path", "/mobile-demo/example.txt")
        searchPrefixInput = input("Search prefix", "/mobile-demo/")
        queryInput = input("Natural-language search query", "feline sofa")
        statusText = TextView(this)
        resultsText = TextView(this)
        progress = ProgressBar(this).apply { visibility = View.GONE }

        root.addView(label("Connection"))
        root.addView(baseUrlInput)
        root.addView(apiKeyInput)
        root.addView(label("Upload"))
        root.addView(remotePathInput)
        root.addView(button("Choose File") { filePicker.launch(arrayOf("*/*")) })
        root.addView(button("Upload File") { upload() })
        root.addView(label("Semantic Search"))
        root.addView(searchPrefixInput)
        root.addView(queryInput)
        root.addView(button("Search") { search() })
        root.addView(progress)
        root.addView(statusText)
        root.addView(resultsText)

        setContentView(ScrollView(this).apply { addView(root) })
        status("Enter an existing Drive9 endpoint and API key.")
    }

    private fun upload() {
        val uri = model.selectedUri
        if (uri == null) {
            status("Choose a file first")
            return
        }
        launchDrive9 {
            val localFile = copyToCache(uri)
            val client = client()
            client.uploadFile(localFile.absolutePath, normalizedPath(remotePathInput.text.toString()))
            status("Uploaded ${localFile.name} to ${normalizedPath(remotePathInput.text.toString())}")
        }
    }

    private fun search() {
        launchDrive9 {
            val client = client()
            val results = client.grep(
                query = queryInput.text.toString().trim(),
                pathPrefix = normalizedPath(searchPrefixInput.text.toString()),
                limit = 20,
            )
            showResults(results)
            status("Found ${results.size} result${if (results.size == 1) "" else "s"}")
        }
    }

    private fun launchDrive9(block: suspend Drive9ExampleViewModel.() -> Unit) {
        progress.visibility = View.VISIBLE
        lifecycleScope.launch {
            try {
                model.block()
            } catch (e: Throwable) {
                status(e.message ?: e.toString())
            } finally {
                progress.visibility = View.GONE
            }
        }
    }

    private fun client(): Drive9Client =
        Drive9Client(
            baseUrl = baseUrlInput.text.toString().trim(),
            apiKey = apiKeyInput.text.toString().trim(),
        )

    private suspend fun copyToCache(uri: Uri): File = withContext(Dispatchers.IO) {
        val name = displayName(uri).ifBlank { "drive9-upload.bin" }
        val file = File(cacheDir, name)
        contentResolver.openInputStream(uri).use { input ->
            requireNotNull(input) { "Cannot open selected file" }
            file.outputStream().use { output -> input.copyTo(output) }
        }
        file
    }

    private fun showResults(results: List<Drive9SearchResult>) {
        resultsText.text = results.joinToString(separator = "\n\n") {
            buildString {
                append(it.path)
                append("\n")
                append(it.name)
                append(" · ")
                append(it.sizeBytes)
                append(" bytes")
                if (it.score != null) append(" · score ${"%.4f".format(it.score)}")
            }
        }
    }

    private fun displayName(uri: Uri): String {
        contentResolver.query(uri, null, null, null, null)?.use { cursor ->
            val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (index >= 0 && cursor.moveToFirst()) {
                return cursor.getString(index)
            }
        }
        return uri.lastPathSegment ?: "drive9-upload.bin"
    }

    private fun normalizedPath(path: String): String {
        val trimmed = path.trim()
        return if (trimmed.startsWith("/")) trimmed else "/$trimmed"
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

class Drive9ExampleViewModel : ViewModel() {
    var selectedUri: Uri? = null
}
