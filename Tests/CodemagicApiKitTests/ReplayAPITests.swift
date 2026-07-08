import Foundation
import Replay
import Testing
@testable import CodemagicApiKit

/// Exercises the networked layer (generated client wrappers, downloader, public-url)
/// against synthetic Replay stubs — no live network, no recorded private data.
@Suite struct ReplayAPITests {
    func client() -> Codemagic { Codemagic(token: "cm_test", session: Replay.session) }

    static let jsonHeaders = ["Content-Type": "application/json"]

    @Test(.replay(stubs: [
        .get("https://api.codemagic.io/apps", 200, jsonHeaders, {
            """
            { "applications": [ { "_id": "aaaaaaaaaaaaaaaaaaaaaaaa", "appName": "demo", "workflowIds": ["wf-1"], "branches": ["main"] } ], "builds": [] }
            """
        })
    ]))
    func listsApps() async throws {
        let apps = try await client().apps()
        #expect(apps.count == 1)
        #expect(apps.first?.appName == "demo")
        #expect(apps.first?._id == "aaaaaaaaaaaaaaaaaaaaaaaa")
    }

    @Test(.replay(stubs: [
        .get("https://api.codemagic.io/builds?appId=demo", 200, jsonHeaders, {
            """
            { "builds": [
              { "_id": "b1", "status": "finished", "branch": "main" },
              { "_id": "b2", "status": "failed", "branch": "dev" }
            ], "applications": [], "nextPageUrl": null }
            """
        })
    ]))
    func listsBuildsAndFindsLatestForBranch() async throws {
        let cm = client()
        let builds = try await cm.builds(appId: "demo")
        #expect(builds.count == 2)
        let latest = try await cm.latestBuild(appId: "demo", branch: "dev")
        #expect(latest?._id == "b2")
    }

    @Test(.replay(stubs: [
        .get("https://api.codemagic.io/builds/b1", 200, jsonHeaders, {
            """
            { "build": { "_id": "b1", "status": "finished", "branch": "main", "artefacts": [ { "name": "TestResults.xcresult.zip", "url": "https://api.codemagic.io/artifacts/a/b/TestResults.xcresult.zip", "path": "a/b/TestResults.xcresult.zip", "size": 1024 } ] } }
            """
        })
    ]))
    func getsBuildDetail() async throws {
        let build = try await client().build(id: "b1")
        #expect(build._id == "b1")
        #expect(build.artefacts?.first?.name == "TestResults.xcresult.zip")
    }

    @Test(.replay(stubs: [
        .post("https://api.codemagic.io/builds/b1/cancel", 200, jsonHeaders, { "{}" })
    ]))
    func cancelReturnsCancelled() async throws {
        #expect(try await client().cancelBuild(id: "b1") == .cancelled)
    }

    @Test(.replay(stubs: [
        .post("https://api.codemagic.io/builds/bfin/cancel", 208, jsonHeaders, { "" })
    ]))
    func cancelReturnsAlreadyFinishedOn208() async throws {
        #expect(try await client().cancelBuild(id: "bfin") == .alreadyFinished)
    }

    @Test(.replay(stubs: [
        .post("https://api.codemagic.io/builds", 200, jsonHeaders, { #"{ "buildId": "new-build-123" }"# })
    ]))
    func startReturnsBuildId() async throws {
        let id = try await client().startBuild(appId: "demo", workflowId: "wf-1", branch: "main", tag: nil)
        #expect(id == "new-build-123")
    }

    @Test(.replay(stubs: [
        .get("https://api.codemagic.io/apps/demo/caches", 200, jsonHeaders, {
            """
            { "caches": [ { "_id": "c1", "appId": "demo", "workflowId": "wf-1", "platform": "macOS", "size": 2048 } ] }
            """
        })
    ]))
    func listsCaches() async throws {
        let caches = try await client().caches(appId: "demo")
        #expect(caches.first?._id == "c1")
        #expect(caches.first?.size == 2048)
    }

    @Test(.replay(stubs: [
        .post("https://api.codemagic.io/artifacts/a/b/app.zip/public-url", 200, jsonHeaders, {
            #"{ "url": "https://api.codemagic.io/artifacts/.signedtoken", "expiresAt": "2026-07-08T18:00:00+00:00" }"#
        })
    ]))
    func mintsPublicURL() async throws {
        let result = try await client().artefactPublicURL(
            artefactPath: "a/b/app.zip",
            expiresAt: Date(timeIntervalSince1970: 1_775_000_000)
        )
        #expect(result.url == "https://api.codemagic.io/artifacts/.signedtoken")
        #expect(result.expiresAt == "2026-07-08T18:00:00+00:00")
    }

    @Test(.replay(stubs: [
        .get("https://api.codemagic.io/builds/b1/step/s9", 200, ["Content-Type": "text/plain; charset=utf-8"], {
            #"<span style="color:#268BD2">[build]</span> $ build\n"#
        })
    ]))
    func fetchesStepLog() async throws {
        let body = try await client().stepLog(logUrl: "https://api.codemagic.io/builds/b1/step/s9")
        #expect(body.contains("[build]"))
        #expect(body.contains("<span"))   // markup preserved by the fetch; the CLI strips it
    }

    @Test(.replay(stubs: [
        .get("https://api.codemagic.io/artifacts/a/b/app.zip", 200, ["Content-Type": "application/octet-stream"], { "PK-fake-bytes" })
    ]))
    func downloadsArtefactToFile() async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cmagic-dl-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let downloader = ArtefactDownloader(token: "cm_test", session: Replay.session)
        let file = try await downloader.download(
            from: URL(string: "https://api.codemagic.io/artifacts/a/b/app.zip")!,
            to: dir
        )
        #expect(file.lastPathComponent == "app.zip")
        #expect(try String(contentsOf: file, encoding: .utf8) == "PK-fake-bytes")
    }
}
