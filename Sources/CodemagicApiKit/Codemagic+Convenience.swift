import Foundation

/// High-level model-returning wrappers over the generated client, so callers
/// don't navigate the generated `Operations.*.Output.Ok.Body.json` chain.
public extension Codemagic {
    typealias Application = Components.Schemas.Application
    typealias Build = Components.Schemas.Build
    typealias BuildAction = Components.Schemas.BuildAction
    typealias Artefact = Components.Schemas.Artefact
    typealias Cache = Components.Schemas.Cache

    /// List applications for the authenticated token.
    func apps() async throws -> [Application] {
        try await underlying.getApps().ok.body.json.applications
    }

    /// First page of builds for an application (newest first, 30 max).
    /// For more than one page use `builds(appId:branch:limit:maxPages:)`.
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

    // MARK: - Caches

    /// List caches for an application.
    func caches(appId: String) async throws -> [Cache] {
        try await underlying.getAppsIdCaches(.init(path: .init(id: appId))).ok.body.json.caches
    }

    /// Delete all caches for an application (async on the server; 202 Accepted).
    func deleteAllCaches(appId: String) async throws {
        _ = try await underlying.deleteAppsIdCaches(.init(path: .init(id: appId))).accepted
    }

    /// Delete a single workflow cache.
    func deleteCache(appId: String, cacheId: String) async throws {
        _ = try await underlying.deleteAppsIdCachesCacheId(.init(path: .init(id: appId, cacheId: cacheId))).accepted
    }

    // MARK: - Build lifecycle

    /// Result of cancelling a build.
    enum CancelOutcome: Sendable { case cancelled, alreadyFinished }

    /// Cancel a build. Returns `.alreadyFinished` when the API reports 208.
    func cancelBuild(id: String) async throws -> CancelOutcome {
        switch try await underlying.postBuildsIdCancel(.init(path: .init(id: id))) {
        case .ok: return .cancelled
        case .code208: return .alreadyFinished
        case .undocumented(let statusCode, _):
            throw CodemagicError.unexpectedStatus(statusCode)
        }
    }

    /// Start a build. Returns the new build id.
    func startBuild(appId: String, workflowId: String, branch: String?, tag: String?) async throws -> String {
        let body = Operations.postBuilds.Input.Body.jsonPayload(
            appId: appId, branch: branch, tag: tag, workflowId: workflowId
        )
        return try await underlying.postBuilds(.init(body: .json(body))).ok.body.json.buildId
    }
}
