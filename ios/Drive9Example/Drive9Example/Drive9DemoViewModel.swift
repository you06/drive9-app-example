import AVFoundation
import Foundation
import Speech
import Drive9Mobile

private let defaultServer = "https://api.drive9.ai"
private let audioPrefix = "/mobile-demo/audio"
private let minimumRecordingBytes: UInt64 = 1024

struct Drive9AudioSearchResult: Identifiable {
    let id = UUID()
    let path: String
    let name: String
    let sizeBytes: Int64
    let score: Double?
    let semanticText: String
}

enum SearchLanguage: String, CaseIterable, Identifiable {
    case zh
    case en
    case ja

    var id: String { rawValue }

    var localeIdentifier: String {
        switch self {
        case .zh: return "zh-CN"
        case .en: return "en-US"
        case .ja: return "ja-JP"
        }
    }

    var displayName: String {
        switch self {
        case .zh: return "中文"
        case .en: return "English"
        case .ja: return "日本語"
        }
    }
}

@MainActor
final class Drive9DemoViewModel: NSObject, ObservableObject {
    @Published var baseURL = defaultServer
    @Published var apiKey = ""
    @Published var isConnected = false
    @Published var status = "Enter an existing Drive9 API key."
    @Published var isError = false
    @Published var isBusy = false
    @Published var uploadRecordingURL: URL?
    @Published var uploadRecordingName: String?
    @Published var isRecordingUpload = false
    @Published var searchLanguage: SearchLanguage = .zh
    @Published var searchTranscript: String = ""
    @Published var isSpeakingSearch = false
    @Published var isTranscribing = false
    @Published var results: [Drive9AudioSearchResult] = []
    @Published var showResults = false

    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var searchRecordingURL: URL?

    var canConnect: Bool {
        !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canUploadRecording: Bool {
        isConnected && uploadRecordingURL != nil && !isRecordingUpload && !isSpeakingSearch && !isBusy && !isTranscribing
    }

    var canSpeakSearch: Bool {
        isConnected && !isRecordingUpload && !isSpeakingSearch && !isBusy && !isTranscribing
    }

    var canSearchByTranscript: Bool {
        isConnected
            && !searchTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isRecordingUpload && !isSpeakingSearch && !isBusy && !isTranscribing
    }

    var isRecording: Bool {
        isRecordingUpload || isSpeakingSearch
    }

    var recordingStatusText: String {
        if isRecordingUpload { return "Recording upload audio... tap Stop Recording when finished." }
        if isSpeakingSearch { return "Listening for search query (\(searchLanguage.displayName))... tap Stop Speaking when finished." }
        return ""
    }

    func connect() {
        guard canConnect else {
            setErrorMessage("Drive9 API key is required.")
            return
        }
        isConnected = true
        setStatus("Connected to \(trimmed(baseURL))")
    }

    func startUploadRecording() {
        Task {
            do {
                try await self.requestMicrophoneAccess()
                try self.startUploadRecorder()
            } catch {
                self.setError(error)
            }
        }
    }

    func stopUploadRecording() {
        recorder?.stop()
        recorder = nil
        isRecordingUpload = false
        if let url = uploadRecordingURL {
            setRecordingReadyStatus(url, label: "Upload recording")
        }
    }

    func startSpeakingSearch() {
        Task {
            do {
                try await self.requestMicrophoneAccess()
                try await self.requestSpeechAccess()
                try self.startSearchRecorder()
            } catch {
                self.setError(error)
            }
        }
    }

    func stopSpeakingSearch() {
        recorder?.stop()
        recorder = nil
        isSpeakingSearch = false
        guard let url = searchRecordingURL else { return }
        do {
            try validateRecordingFile(url)
        } catch {
            cleanupSearchRecording()
            setError(error)
            return
        }
        Task { await self.transcribeSearchRecording(url) }
    }

    func uploadRecording() async {
        guard let url = uploadRecordingURL else { return }
        do {
            try validateRecordingFile(url)
        } catch {
            setError(error)
            return
        }
        await runBusy {
            let remotePath = "\(audioPrefix)/\(url.lastPathComponent)"
            self.setStatus("Uploading saved recording to \(remotePath)...")
            try await self.client().uploadFile(localPath: url.path, remotePath: remotePath)
            self.setStatus("Uploaded recording to \(remotePath)")
        }
    }

    func searchByTranscript() async {
        let query = searchTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            setErrorMessage("Search transcript is empty.")
            return
        }
        await runBusy {
            self.setStatus("Searching \(audioPrefix) for \"\(query)\"...")
            let hits = try await self.client().grep(query: query, pathPrefix: audioPrefix, limit: 20)
            var enriched: [Drive9AudioSearchResult] = []
            for hit in hits {
                let meta = try? await self.client().statMetadata(path: hit.path)
                enriched.append(
                    Drive9AudioSearchResult(
                        path: hit.path,
                        name: hit.name,
                        sizeBytes: hit.sizeBytes,
                        score: hit.score,
                        semanticText: meta?.semanticText.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    )
                )
            }
            self.results = enriched
            self.showResults = true
            self.setStatus("Found \(enriched.count) recording\(enriched.count == 1 ? "" : "s") for \"\(query)\"")
        }
    }

    func play(_ result: Drive9AudioSearchResult) async {
        await runBusy {
            let localURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("drive9-play-\(UUID().uuidString)-\(result.name.ifEmpty("audio.m4a"))")
            try await self.client().downloadFile(remotePath: result.path, localPath: localURL.path)
            self.player = try AVAudioPlayer(contentsOf: localURL)
            self.player?.prepareToPlay()
            self.player?.play()
            self.setStatus("Playing \(result.name.ifEmpty(result.path))")
        }
    }

    private func startUploadRecorder() throws {
        let url = try beginRecording()
        uploadRecordingURL = url
        uploadRecordingName = url.lastPathComponent
        isRecordingUpload = true
        setStatus("Recording upload audio...")
    }

    private func startSearchRecorder() throws {
        let url = try beginRecording()
        searchRecordingURL = url
        isSpeakingSearch = true
        setStatus("Listening for search query (\(searchLanguage.displayName))...")
    }

    private func beginRecording() throws -> URL {
        if isRecordingUpload || isSpeakingSearch {
            throw Drive9DemoError.message("Stop the current recording first.")
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true)

        let name = "recording-\(Int(Date().timeIntervalSince1970)).m4a"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        let audioRecorder = try AVAudioRecorder(url: url, settings: settings)
        guard audioRecorder.prepareToRecord() else {
            throw Drive9DemoError.message("Failed to prepare audio recorder.")
        }
        guard audioRecorder.record() else {
            throw Drive9DemoError.message("Failed to start audio recorder.")
        }
        recorder = audioRecorder
        return url
    }

    private func requestMicrophoneAccess() async throws {
        try await withCheckedThrowingContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { allowed in
                if allowed {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: Drive9DemoError.message("Microphone permission is required."))
                }
            }
        }
    }

    private func requestSpeechAccess() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            SFSpeechRecognizer.requestAuthorization { status in
                if status == .authorized {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: Drive9DemoError.message("Speech recognition permission is required."))
                }
            }
        }
    }

    private func transcribeSearchRecording(_ url: URL) async {
        isTranscribing = true
        let language = searchLanguage
        setStatus("Transcribing search query in \(language.displayName)...")
        let locale = Locale(identifier: language.localeIdentifier)
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            isTranscribing = false
            cleanupSearchRecording()
            setErrorMessage("Speech recognizer is not available for \(language.displayName).")
            return
        }
        guard recognizer.isAvailable else {
            isTranscribing = false
            cleanupSearchRecording()
            setErrorMessage("Speech recognizer for \(language.displayName) is not available right now.")
            return
        }
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        do {
            let text = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
                let state = TranscriptionContinuationState()
                recognizer.recognitionTask(with: request) { result, error in
                    if let error = error {
                        state.finish(continuation: continuation, .failure(error))
                        return
                    }
                    guard let result = result, result.isFinal else { return }
                    state.finish(continuation: continuation, .success(result.bestTranscription.formattedString))
                }
            }
            let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            searchTranscript = trimmedText
            if trimmedText.isEmpty {
                setErrorMessage("Could not transcribe the recording. Try speaking more clearly and retry.")
            } else {
                setStatus("Heard: \(trimmedText)")
            }
        } catch {
            setError(error)
        }
        isTranscribing = false
        cleanupSearchRecording()
    }

    private func cleanupSearchRecording() {
        if let url = searchRecordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        searchRecordingURL = nil
    }

    private func validateRecordingFile(_ url: URL) throws {
        try validateRecordingSize(try recordingFileSize(url))
    }

    private func setRecordingReadyStatus(_ url: URL, label: String) {
        do {
            let size = try recordingFileSize(url)
            try validateRecordingSize(size)
            setStatus("\(label) ready: \(url.lastPathComponent) (\(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)))")
        } catch {
            setError(error)
        }
    }

    private func recordingFileSize(_ url: URL) throws -> UInt64 {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs[.size] as? NSNumber)?.uint64Value ?? 0
    }

    private func validateRecordingSize(_ size: UInt64) throws {
        if size < minimumRecordingBytes {
            throw Drive9DemoError.message("Recording file is only \(size) bytes. Record for a few seconds and try again.")
        }
    }

    private func runBusy(_ action: @escaping () async throws -> Void) async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await action()
        } catch {
            setError(error)
        }
    }

    private func client() -> Drive9Client {
        Drive9Client(baseUrl: trimmed(baseURL), apiKey: trimmed(apiKey))
    }

    private func setStatus(_ message: String) {
        isError = false
        status = message
    }

    private func setError(_ error: Error) {
        setErrorMessage(error.localizedDescription)
    }

    private func setErrorMessage(_ message: String) {
        isError = true
        status = message
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum Drive9DemoError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case let .message(value):
            return value
        }
    }
}

private final class TranscriptionContinuationState: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func finish(continuation: CheckedContinuation<String, Error>, _ outcome: Result<String, Error>) {
        lock.lock()
        let shouldResume = !done
        done = true
        lock.unlock()
        guard shouldResume else { return }
        continuation.resume(with: outcome)
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}
