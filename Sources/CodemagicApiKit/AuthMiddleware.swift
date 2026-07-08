import Foundation
import HTTPTypes
import OpenAPIRuntime

/// Injects the Codemagic `x-auth-token` header on every request.
struct AuthMiddleware: ClientMiddleware {
    let token: String

    func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var request = request
        request.headerFields[.init("x-auth-token")!] = token
        return try await next(request, body, baseURL)
    }
}
