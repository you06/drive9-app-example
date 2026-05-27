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

    var body: some View {
        NavigationStack {
            Form {
                Section("Drive9") {
                    TextField("Server", text: $model.baseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)

                    SecureField("API key", text: $model.apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Button("Continue") {
                        model.connect()
                    }
                    .disabled(!model.canConnect)
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
                Section("Upload Recording") {
                    if let name = model.uploadRecordingName {
                        Text(name)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Button(model.isRecordingUpload ? "Stop Recording" : "Record Upload") {
                            if model.isRecordingUpload {
                                model.stopRecording(.upload)
                            } else {
                                model.startRecording(.upload)
                            }
                        }

                        Button("Upload") {
                            Task { await model.uploadRecording() }
                        }
                        .disabled(!model.canUploadRecording)
                    }
                }

                Section("Search Recording") {
                    if let name = model.searchRecordingName {
                        Text(name)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Button(model.isRecordingSearch ? "Stop Recording" : "Record Query") {
                            if model.isRecordingSearch {
                                model.stopRecording(.search)
                            } else {
                                model.startRecording(.search)
                            }
                        }

                        Button("Search") {
                            Task { await model.searchRecording() }
                        }
                        .disabled(!model.canSearchRecording)
                    }
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
