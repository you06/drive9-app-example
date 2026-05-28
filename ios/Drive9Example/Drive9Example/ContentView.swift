import SwiftUI

struct ContentView: View {
    @StateObject private var model = Drive9DemoViewModel()

    var body: some View {
        Group {
            if !model.isConnected {
                ConnectionView(model: model)
            } else if model.showResults {
                ResultsView(model: model)
            } else {
                MainDemoView(model: model)
            }
        }
    }
}

private struct TopBar: View {
    let title: String
    let topInset: CGFloat
    let onBack: (() -> Void)?

    init(title: String, topInset: CGFloat, onBack: (() -> Void)? = nil) {
        self.title = title
        self.topInset = topInset
        self.onBack = onBack
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            HStack {
                if let onBack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .padding(.horizontal, 4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back")
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)

            Text(title)
                .font(.headline)
                .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity)
        .frame(height: topInset + 36)
        .background(Color(.systemBackground))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

private struct ScreenLayout<Content: View>: View {
    let title: String
    let onBack: (() -> Void)?
    @ViewBuilder let content: (CGFloat) -> Content

    init(title: String, onBack: (() -> Void)? = nil, @ViewBuilder content: @escaping (CGFloat) -> Content) {
        self.title = title
        self.onBack = onBack
        self.content = content
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                TopBar(title: title, topInset: proxy.safeAreaInsets.top, onBack: onBack)
                content(proxy.safeAreaInsets.bottom)
            }
        }
        .ignoresSafeArea()
        .background(Color(.systemBackground))
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
        ScreenLayout(title: "Drive9") { _ in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    CardSection(title: "Drive9") {
                        TextField("Server", text: $serverInput)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .textContentType(.URL)
                            .textFieldStyle(.roundedBorder)

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
                            .textFieldStyle(.roundedBorder)

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
                        .buttonStyle(.borderedProminent)
                        .disabled(!canContinue)
                    }

                    Text(model.status)
                        .font(.footnote)
                        .foregroundStyle(model.isError ? .red : .secondary)
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 12)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }
}

private struct MainDemoView: View {
    @ObservedObject var model: Drive9DemoViewModel

    var body: some View {
        ScreenLayout(title: "Drive9 Audio") { _ in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if model.isRecording {
                        CardSection(title: "Recording") {
                            HStack(spacing: 12) {
                                ProgressView()
                                Text(model.recordingStatusText)
                                    .foregroundStyle(.red)
                                    .font(.footnote)
                            }
                        }
                    }

                    CardSection(title: "Upload Recording") {
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

                    CardSection(title: "Search") {
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
                            .textFieldStyle(.roundedBorder)
                            .disabled(model.isSpeakingSearch || model.isTranscribing)

                        Button("Search Recordings") {
                            Task { await model.searchByTranscript() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!model.canSearchByTranscript)
                    }

                    HStack(spacing: 8) {
                        if model.isBusy {
                            ProgressView()
                        }
                        Text(model.status)
                            .font(.footnote)
                            .foregroundStyle(model.isError ? .red : .secondary)
                    }
                    .padding(.horizontal, 4)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 12)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }
}

private struct ResultsView: View {
    @ObservedObject var model: Drive9DemoViewModel

    var body: some View {
        ScreenLayout(title: "Results", onBack: { model.showResults = false }) { _ in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if model.results.isEmpty {
                        Text("No recordings found.")
                            .foregroundStyle(.secondary)
                            .padding(.top, 24)
                    }

                    ForEach(model.results) { result in
                        CardSection(title: result.name.ifEmpty(result.path)) {
                            Text(result.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text(result.semanticText.ifEmpty("No semantic summary yet."))
                                .font(.body)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)

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
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 12)
            }
        }
    }
}

private struct CardSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}
