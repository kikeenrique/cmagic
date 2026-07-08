import Foundation
import OpenAPIRuntime
import OpenAPIURLSession

/// Entry point for the Codemagic v1 REST API.
///
/// Wraps the generated OpenAPI ``Client`` with the `x-auth-token` auth middleware
/// and the fixed `https://api.codemagic.io` base URL.
public struct Codemagic: Sendable {
    /// The generated OpenAPI client. Call operations like `underlying.getApps(_:)`.
    public let underlying: Client
    /// The API token (also used by direct-URLSession helpers for endpoints the
    /// generated client can't express, e.g. artefact download / public-url).
    public let token: String
    let session: URLSession

    public static let baseURL = URL(string: "https://api.codemagic.io")!

    /// Create a client with an explicit token.
    public init(token: String, session: URLSession = .shared) {
        self.token = token
        self.session = session
        let transport = URLSessionTransport(configuration: .init(session: session))
        self.underlying = Client(
            serverURL: Codemagic.baseURL,
            transport: transport,
            middlewares: [AuthMiddleware(token: token)]
        )
    }

    /// Create a client using the token from the config file (see ``CmagicConfig``).
    public static func fromConfig() throws -> Codemagic {
        Codemagic(token: try CmagicConfig.load().token)
    }
}
