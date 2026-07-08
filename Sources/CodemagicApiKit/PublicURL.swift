import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Response of the artefact public-url endpoint.
public struct ArtefactPublicURL: Sendable, Codable {
    public let url: String
    /// ISO-8601 expiry as returned by the API (the request sends UNIX seconds).
    public let expiresAt: String?
}

public extension Codemagic {
    /// Create a tokenless public download URL for an artefact.
    ///
    /// Uses `URLSession` directly: the `/artifacts/<path>/public-url` endpoint has a
    /// multi-segment `secureFilename` the generated client can't express.
    /// - Parameters:
    ///   - artefactPath: the artefact's `path` (`<build-id>/<artifact-id>/<filename>`).
    ///   - expiresAt: when the public URL should stop working.
    func artefactPublicURL(artefactPath: String, expiresAt: Date) async throws -> ArtefactPublicURL {
        let urlString = Codemagic.baseURL.absoluteString + "/artifacts/" + artefactPath + "/public-url"
        guard let url = URL(string: urlString) else { throw CodemagicError.invalidURL(urlString) }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(token, forHTTPHeaderField: "x-auth-token")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: ["expiresAt": Int(expiresAt.timeIntervalSince1970)]
        )

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw CodemagicError.badResponse(http.statusCode)
        }
        return try JSONDecoder().decode(ArtefactPublicURL.self, from: data)
    }
}
