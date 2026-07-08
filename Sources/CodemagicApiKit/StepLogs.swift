import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public extension Codemagic {
    /// Fetch the log for one build step.
    ///
    /// Uses `URLSession` directly: `logUrl` is a full `…/builds/<id>/step/<stepId>`
    /// URL the generated client doesn't model. The body is `text/plain` but wraps
    /// each line in `<span style="color:…">` markup for terminal colouring.
    /// - Parameter logUrl: a `BuildAction.logUrl` (or subaction `logUrl`).
    func stepLog(logUrl: String) async throws -> String {
        guard let url = URL(string: logUrl) else { throw CodemagicError.invalidURL(logUrl) }
        var request = URLRequest(url: url)
        request.setValue(token, forHTTPHeaderField: "x-auth-token")

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw CodemagicError.badResponse(http.statusCode)
        }
        return String(decoding: data, as: UTF8.self)
    }
}
