import Foundation
import Testing
@testable import CodemagicApiKit

/// Decode synthetic JSON (shaped like the verified live responses) into the
/// generated model types. Values are fake — no private data.
@Suite struct ModelDecodingTests {
    let decoder = JSONDecoder()

    @Test func decodesApplication() throws {
        let json = Data("""
        {
          "_id": "aaaaaaaaaaaaaaaaaaaaaaaa",
          "appName": "demo",
          "workflowIds": ["wf-1", "wf-2"],
          "branches": ["main", "dev"],
          "projectType": null,
          "extraFieldTheDocsDontMention": true
        }
        """.utf8)
        let app = try decoder.decode(Codemagic.Application.self, from: json)
        #expect(app._id == "aaaaaaaaaaaaaaaaaaaaaaaa")
        #expect(app.appName == "demo")
        #expect(app.workflowIds == ["wf-1", "wf-2"])
        #expect(app.branches == ["main", "dev"])
        #expect(app.projectType == nil)
    }

    @Test func decodesBuildWithArtefactsAndNullWorkflowId() throws {
        let json = Data("""
        {
          "_id": "bbbbbbbbbbbbbbbbbbbbbbbb",
          "status": "finished",
          "branch": "main",
          "tag": null,
          "workflowId": null,
          "fileWorkflowId": "build-and-test",
          "artefacts": [
            { "name": "app_artifacts.zip", "type": "bundle", "url": "https://example.test/a/b/app_artifacts.zip", "path": "a/b/app_artifacts.zip", "size": 6093048, "versionName": null }
          ]
        }
        """.utf8)
        let build = try decoder.decode(Codemagic.Build.self, from: json)
        #expect(build._id == "bbbbbbbbbbbbbbbbbbbbbbbb")
        #expect(build.status == "finished")
        #expect(build.workflowId == nil)               // null under codemagic.yaml
        #expect(build.fileWorkflowId == "build-and-test")
        #expect(build.artefacts?.count == 1)
        let art = try #require(build.artefacts?.first)
        #expect(art.name == "app_artifacts.zip")
        #expect(art.size == 6_093_048)
        #expect(art.url == "https://example.test/a/b/app_artifacts.zip")
    }

    @Test func decodesBuildActionsWithSubactions() throws {
        let json = Data("""
        {
          "_id": "bbbbbbbbbbbbbbbbbbbbbbbb",
          "status": "finished",
          "buildActions": [
            { "_id": "s1", "name": "Preparing build machine", "type": "preparing", "status": "success",
              "startedAt": "2026-07-08T18:24:20.540000+00:00", "finishedAt": "2026-07-08T18:25:19.374000+00:00",
              "logUrl": "https://example.test/builds/b/step/s1", "results": [], "subactions": [] },
            { "_id": "s2", "name": "Install tools via mise", "type": null, "status": "success",
              "startedAt": "2026-07-08T18:25:38.000000+00:00", "finishedAt": "2026-07-08T18:25:39.000000+00:00",
              "subactions": [
                { "command": "#!/usr/bin/env bash\\nmise install", "status": "success",
                  "logUrl": "https://example.test/builds/b/step/s2a" }
              ] }
          ]
        }
        """.utf8)
        let build = try decoder.decode(Codemagic.Build.self, from: json)
        #expect(build.buildActions?.count == 2)
        let first = try #require(build.buildActions?.first)
        #expect(first.name == "Preparing build machine")
        #expect(first._type == "preparing")
        #expect(first.status == "success")
        #expect(first.logUrl == "https://example.test/builds/b/step/s1")
        let second = try #require(build.buildActions?.last)
        #expect(second._type == nil)                         // script steps have no type
        #expect(second.subactions?.count == 1)
        let sub = try #require(second.subactions?.first)
        #expect(sub.command?.contains("mise install") == true)
        #expect(sub.name == nil)                             // subactions carry a command, not a name
    }

    @Test func decodesCache() throws {
        let json = Data("""
        { "_id": "cccccccccccccccccccccccc", "appId": "aaaaaaaaaaaaaaaaaaaaaaaa", "workflowId": "build-and-test", "platform": "macOS (Apple silicon)", "size": 385515520 }
        """.utf8)
        let cache = try decoder.decode(Codemagic.Cache.self, from: json)
        #expect(cache._id == "cccccccccccccccccccccccc")
        #expect(cache.platform == "macOS (Apple silicon)")
        #expect(cache.size == 385_515_520)
    }

    @Test func artefactRequiresURL() {
        let json = Data(#"{ "name": "no-url" }"#.utf8)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(Codemagic.Artefact.self, from: json)
        }
    }
}
