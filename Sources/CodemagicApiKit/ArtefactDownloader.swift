import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Downloads build artefacts directly over `URLSession`.
///
/// The generated client cannot express the `/artifacts/<build>/<artifact>/<file>`
/// endpoint (its `secureFilename` path parameter spans "/"). Instead we fetch the
/// full `build.artefacts[].url` with the `x-auth-token` header — which is exactly
/// what that URL is for.
public struct ArtefactDownloader: Sendable {
    let token: String
    let session: URLSession

    public init(token: String, session: URLSession = .shared) {
        self.token = token
        self.session = session
    }

    /// Download the artefact at `url` to `destination`, returning the file URL.
    /// `destination` may be a directory (the URL's last path component is used) or a full file path.
    @discardableResult
    public func download(from url: URL, to destination: URL) async throws -> URL {
        var request = URLRequest(url: url)
        request.setValue(token, forHTTPHeaderField: "x-auth-token")

        let (tempURL, response) = try await session.download(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ArtefactDownloadError.badStatus(http.statusCode, url: url)
        }

        let fm = FileManager.default
        var target = destination
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: destination.path, isDirectory: &isDir), isDir.boolValue {
            target = destination.appendingPathComponent(url.lastPathComponent)
        }
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
        try fm.moveItem(at: tempURL, to: target)
        return target
    }
}

public enum ArtefactDownloadError: Error, CustomStringConvertible, Sendable {
    case badStatus(Int, url: URL)

    public var description: String {
        switch self {
        case .badStatus(let code, let url):
            return "Artefact download failed with HTTP \(code): \(url.absoluteString)"
        }
    }
}
