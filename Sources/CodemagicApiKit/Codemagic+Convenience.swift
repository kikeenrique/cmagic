import Foundation

/// High-level model-returning wrappers over the generated client, so callers
/// don't navigate the generated `Operations.*.Output.Ok.Body.json` chain.
public extension Codemagic {
    typealias Application = Components.Schemas.Application
    typealias Build = Components.Schemas.Build
    typealias Artefact = Components.Schemas.Artefact

    /// List applications for the authenticated token.
    func apps() async throws -> [Application] {
        try await underlying.getApps().ok.body.json.applications
    }

    /// List builds for an application (newest first; first page only — see `nextPageUrl`).
    func builds(appId: String) async throws -> [Build] {
        try await underlying.listBuilds(.init(query: .init(appId: appId))).ok.body.json.builds
    }

    /// Fetch a single build by id.
    func build(id: String) async throws -> Build {
        try await underlying.getBuild(.init(path: .init(id: id))).ok.body.json.build
    }

    /// The most recent build for `appId`, optionally filtered to `branch`.
    /// Returns nil when no build matches.
    func latestBuild(appId: String, branch: String? = nil) async throws -> Build? {
        let all = try await builds(appId: appId)
        guard let branch else { return all.first }
        return all.first { $0.branch == branch }
    }
}
