import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var model = Drive9DemoViewModel()
    @State private var showingImporter = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    TextField("Base URL", text: $model.baseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)

                    SecureField("Drive9 API key", text: $model.apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("Upload") {
                    TextField("Remote path", text: $model.remotePath)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    if let selectedFileName = model.selectedFileName {
                        Text(selectedFileName)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Button("Choose File") {
                        showingImporter = true
                    }

                    Button("Upload File") {
                        Task { await model.uploadSelectedFile() }
                    }
                    .disabled(!model.canUpload)
                }

                Section("Semantic Search") {
                    TextField("Search prefix", text: $model.searchPrefix)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    TextField("Natural-language query", text: $model.query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Button("Search") {
                        Task { await model.search() }
                    }
                    .disabled(!model.canSearch)

                    ForEach(model.results) { result in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(result.path)
                                .font(.headline)
                            HStack {
                                Text(result.name)
                                Spacer()
                                Text(ByteCountFormatter.string(fromByteCount: result.sizeBytes, countStyle: .file))
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)

                            if let score = result.score {
                                Text("score \(score, specifier: "%.4f")")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section {
                    Text(model.status)
                        .font(.footnote)
                        .foregroundStyle(model.isError ? .red : .secondary)
                }
            }
            .navigationTitle("Drive9 Demo")
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
                model.handleFileImport(result)
            }
        }
    }
}

