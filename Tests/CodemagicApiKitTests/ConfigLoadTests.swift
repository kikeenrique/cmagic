import Foundation
import Testing
@testable import CodemagicApiKit

@Suite struct ConfigLoadTests {
    /// Write `contents` to a unique temp file and return its path.
    func tempConfig(_ contents: String) throws -> String {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cmagic-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("config.toml")
        try contents.write(to: file, atomically: true, encoding: .utf8)
        return file.path
    }

    @Test func loadsTokenAppAndBranch() throws {
        let path = try tempConfig("""
        token = "cm_abc"
        app = "664aabbccddee"
        branch = "main"
        """)
        let config = try CmagicConfig.load(path: path)
        #expect(config.token == "cm_abc")
        #expect(config.app == "664aabbccddee")
        #expect(config.branch == "main")
    }

    @Test func defaultsAppAndBranchToNil() throws {
        let path = try tempConfig(#"token = "cm_only""#)
        let config = try CmagicConfig.load(path: path)
        #expect(config.token == "cm_only")
        #expect(config.app == nil)
        #expect(config.branch == nil)
    }

    @Test func missingFileThrows() {
        #expect(throws: CodemagicError.self) {
            try CmagicConfig.load(path: "/nonexistent/cmagic/config.toml")
        }
    }

    @Test func missingTokenThrows() throws {
        let path = try tempConfig(#"app = "x""#)
        #expect(throws: CodemagicError.self) {
            try CmagicConfig.load(path: path)
        }
    }
}
