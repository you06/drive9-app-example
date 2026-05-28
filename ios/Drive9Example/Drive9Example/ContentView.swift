import SwiftUI

struct ContentView: View {
    @StateObject private var model = Drive9DemoViewModel()

    var body: some View {
        Group {
            if model.isConnected {
                MainDemoView(model: model)
            } else {
                ConnectionView(model: model)
            }
        }
    }
}

private struct ConnectionView: View {
    @ObservedObject var model: Drive9DemoViewModel
    @State private var serverInput: String
    @State private var keyInput: String
    @State private var showKey = false

    init(model: Drive9DemoViewModel) {
        self.model = model
        _serverInput = State(initialValue: model.baseURL)
        _keyInput = State(initialValue: model.apiKey)
    }

    private var canContinue: Bool {
        !serverInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !keyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Drive9") {
                    TextField("Server", text: $serverInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .textContentType(.URL)

                    HStack {
                        Group {
                            if showKey {
                                TextField("API key", text: $keyInput)
                            } else {
                                SecureField("API key", text: $keyInput)
                            }
                        }
                        .textContentType(.oneTimeCode)
                        .keyboardType(.asciiCapable)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                        Button(showKey ? "Hide" : "Show") {
                            showKey.toggle()
                        }
                        .buttonStyle(.bordered)
                    }

                    Button("Continue") {
                        model.baseURL = serverInput
                        model.apiKey = keyInput
                        model.connect()
                    }
                    .disabled(!canContinue)
                }

                Section {
                    Text(model.status)
                        .font(.footnote)
                        .foregroundStyle(model.isError ? .red : .secondary)
                }
            }
            .navigationTitle("Drive9")
        }
    }
}

private struct MainDemoView: View {
    @ObservedObject var model: Drive9DemoViewModel

    var body: some View {
        NavigationStack {
            Form {
                if model.isRecording {
                    Section("Recording") {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text(model.recordingStatusText)
                                .foregroundStyle(.red)
                        }
                    }
                }

                Section("Upload Recording") {
                    if let name = model.uploadRecordingName {
                        Text(name)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Button(model.isRecordingUpload ? "Stop Upload Recording" : "Record Upload Audio") {
                            if model.isRecordingUpload {
                                model.stopUploadRecording()
                            } else {
                                model.startUploadRecording()
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(model.isSpeakingSearch || model.isBusy || model.isTranscribing)

                        Button("Upload Saved Recording") {
                            Task { await model.uploadRecording() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!model.canUploadRecording)
                    }
                }

                Section("Search") {
                    Picker("Language", selection: $model.searchLanguage) {
                        ForEach(SearchLanguage.allCases) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(model.isSpeakingSearch || model.isTranscribing)

                    HStack {
                        Button(model.isSpeakingSearch ? "Stop Speaking" : "Speak Search Query") {
                            if model.isSpeakingSearch {
                                model.stopSpeakingSearch()
                            } else {
                                model.startSpeakingSearch()
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(!model.canSpeakSearch && !model.isSpeakingSearch)

                        if model.isTranscribing {
                            ProgressView()
                        }
                    }

                    TextField("Search query", text: $model.searchTranscript, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .lineLimit(1...3)
                        .disabled(model.isSpeakingSearch || model.isTranscribing)

                    Button("Search Recordings") {
                        Task { await model.searchByTranscript() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canSearchByTranscript)
                }

                Section {
                    if model.isBusy {
                        ProgressView()
                    }

                    Text(model.status)
                        .font(.footnote)
                        .foregroundStyle(model.isError ? .red : .secondary)
                }
            }
            .navigationTitle("Drive9 Audio")
            .navigationDestination(isPresented: $model.showResults) {
                ResultsView(model: model)
            }
        }
    }
}

private struct ResultsView: View {
    @ObservedObject var model: Drive9DemoViewModel

    var body: some View {
        List {
            if model.results.isEmpty {
                Text("No recordings found.")
                    .foregroundStyle(.secondary)
            }

            ForEach(model.results) { result in
                VStack(alignment: .leading, spacing: 8) {
                    Text(result.name.ifEmpty(result.path))
                        .font(.headline)

                    Text(result.semanticText.ifEmpty("No semantic summary is available."))
                        .font(.body)
                        .foregroundStyle(.secondary)

                    HStack {
                        Text(ByteCountFormatter.string(fromByteCount: result.sizeBytes, countStyle: .file))
                        if let score = result.score {
                            Text("score \(score, specifier: "%.4f")")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Button("Play Audio") {
                        Task { await model.play(result) }
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.isBusy)
                }
                .padding(.vertical, 6)
            }
        }
        .navigationTitle("Results")
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}
