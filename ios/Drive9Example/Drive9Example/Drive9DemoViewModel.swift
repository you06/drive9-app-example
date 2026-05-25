import Foundation
import Drive9Mobile

struct Drive9DemoSearchResult: Identifiable {
    let id = UUID()
    let path: String
    let name: String
    let sizeBytes: Int64
    let score: Double?
}

@MainActor
final class Drive9DemoViewModel: ObservableObject {
    @Published var baseURL = "https://"
    @Published var apiKey = ""
    @Published var remotePath = "/mobile-demo/example.txt"
    @Published var searchPrefix = "/mobile-demo/"
    @Published var query = "feline sofa"
    @Published var selectedFileURL: URL?
    @Published var selectedFileName: String?
    @Published var status = "Enter an existing Drive9 endpoint and API key."
    @Published var isError = false
    @Published var results: [Drive9DemoSearchResult] = []

    var canUpload: Bool {
        hasConnection && selectedFileURL != nil && !remotePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canSearch: Bool {
        hasConnection && !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasConnection: Bool {
        baseURL.hasPrefix("http") && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func handleFileImport(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            selectedFileURL = url
            selectedFileName = url.lastPathComponent
            if remotePath == "/mobile-demo/example.txt" {
                remotePath = "/mobile-demo/\(url.lastPathComponent)"
            }
            setStatus("Selected \(url.lastPathComponent)")
        } catch {
            setError(error)
        }
    }

    func uploadSelectedFile() async {
        guard let url = selectedFileURL else { return }
        do {
            let scoped = url.startAccessingSecurityScopedResource()
            defer {
                if scoped { url.stopAccessingSecurityScopedResource() }
            }

            let client = Drive9Client(baseUrl: trimmed(baseURL), apiKey: trimmed(apiKey))
            try await client.uploadFile(localPath: url.path, remotePath: normalizedPath(remotePath))
            setStatus("Uploaded \(url.lastPathComponent) to \(normalizedPath(remotePath))")
        } catch {
            setError(error)
        }
    }

    func search() async {
        do {
            let client = Drive9Client(baseUrl: trimmed(baseURL), apiKey: trimmed(apiKey))
            let response = try await client.grep(query: trimmed(query), pathPrefix: normalizedPath(searchPrefix), limit: 20)
            results = response.map {
                Drive9DemoSearchResult(path: $0.path, name: $0.name, sizeBytes: $0.sizeBytes, score: $0.score)
            }
            setStatus("Found \(results.count) result\(results.count == 1 ? "" : "s")")
        } catch {
            setError(error)
        }
    }

    private func setStatus(_ message: String) {
        isError = false
        status = message
    }

    private func setError(_ error: Error) {
        isError = true
        status = error.localizedDescription
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedPath(_ path: String) -> String {
        let value = trimmed(path)
        return value.hasPrefix("/") ? value : "/\(value)"
    }
}
