import AVFoundation
import Foundation
import Drive9Mobile

private let defaultServer = "https://api.drive9.ai"
private let audioPrefix = "/mobile-demo/audio"
private let queryTmpPrefix = "/mobile-demo/tmp-query"
private let minimumRecordingBytes: UInt64 = 1024

struct Drive9AudioSearchResult: Identifiable {
    let id = UUID()
    let path: String
    let name: String
    let sizeBytes: Int64
    let score: Double?
    let semanticText: String
}

enum RecordingPurpose {
    case upload
    case search
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
    @Published var searchRecordingURL: URL?
    @Published var searchRecordingName: String?
    @Published var isRecordingUpload = false
    @Published var isRecordingSearch = false
    @Published var results: [Drive9AudioSearchResult] = []
    @Published var showResults = false

    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?

    var canConnect: Bool {
        !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canUploadRecording: Bool {
        isConnected && uploadRecordingURL != nil && !isRecordingUpload && !isRecordingSearch && !isBusy
    }

    var canSearchRecording: Bool {
        isConnected && searchRecordingURL != nil && !isRecordingUpload && !isRecordingSearch && !isBusy
    }

    var isRecording: Bool {
        isRecordingUpload || isRecordingSearch
    }

    var recordingStatusText: String {
        if isRecordingUpload { return "Recording upload audio... tap Stop Recording when finished." }
        if isRecordingSearch { return "Recording search query... tap Stop Recording when finished." }
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

    func startRecording(_ purpose: RecordingPurpose) {
        Task {
            do {
                try await requestMicrophoneAccess()
                try startRecorder(for: purpose)
            } catch {
                setError(error)
            }
        }
    }

    func stopRecording(_ purpose: RecordingPurpose) {
        recorder?.stop()
        recorder = nil
        switch purpose {
        case .upload:
            isRecordingUpload = false
            if let url = uploadRecordingURL {
                setRecordingReadyStatus(url, label: "Upload recording")
            }
        case .search:
            isRecordingSearch = false
            if let url = searchRecordingURL {
                setRecordingReadyStatus(url, label: "Search recording")
            }
        }
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
            try await client().uploadFile(localPath: url.path, remotePath: remotePath)
            setStatus("Uploaded recording to \(remotePath)")
        }
    }

    func searchRecording() async {
        guard let url = searchRecordingURL else { return }
        do {
            try validateRecordingFile(url)
        } catch {
            setError(error)
            return
        }
        await runBusy {
            let hits = try await client().searchByFile(
                localPath: url.path,
                tmpPrefix: queryTmpPrefix,
                searchPrefix: audioPrefix,
                limit: 20,
                timeoutSeconds: 60,
                pollIntervalSeconds: 1
            )
            var enriched: [Drive9AudioSearchResult] = []
            for hit in hits {
                let meta = try? await client().statMetadata(path: hit.path)
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
            results = enriched
            showResults = true
            setStatus("Found \(enriched.count) recording\(enriched.count == 1 ? "" : "s")")
        }
    }

    func play(_ result: Drive9AudioSearchResult) async {
        await runBusy {
            let localURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("drive9-play-\(UUID().uuidString)-\(result.name.ifEmpty("audio.m4a"))")
            try await client().downloadFile(remotePath: result.path, localPath: localURL.path)
            player = try AVAudioPlayer(contentsOf: localURL)
            player?.prepareToPlay()
            player?.play()
            setStatus("Playing \(result.name.ifEmpty(result.path))")
        }
    }

    private func startRecorder(for purpose: RecordingPurpose) throws {
        if isRecordingUpload || isRecordingSearch {
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

        switch purpose {
        case .upload:
            uploadRecordingURL = url
            uploadRecordingName = name
            isRecordingUpload = true
            setStatus("Recording upload audio...")
        case .search:
            searchRecordingURL = url
            searchRecordingName = name
            isRecordingSearch = true
            setStatus("Recording search query...")
        }
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

private extension String {
    func ifEmpty(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}
