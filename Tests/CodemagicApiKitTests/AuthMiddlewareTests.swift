import Foundation
import HTTPTypes
import Testing
@testable import CodemagicApiKit

@Suite struct AuthMiddlewareTests {
    @Test func injectsAuthTokenHeader() async throws {
        let middleware = AuthMiddleware(token: "cm_secret")
        let request = HTTPRequest(method: .get, scheme: "https", authority: "api.codemagic.io", path: "/apps")

        var seenToken: String?
        _ = try await middleware.intercept(
            request,
            body: nil,
            baseURL: Codemagic.baseURL,
            operationID: "getApps"
        ) { forwarded, _, _ in
            seenToken = forwarded.headerFields[.init("x-auth-token")!]
            return (HTTPResponse(status: .ok), nil)
        }

        #expect(seenToken == "cm_secret")
    }
}
