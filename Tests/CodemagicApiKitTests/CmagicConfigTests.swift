import Testing
@testable import CodemagicApiKit

@Suite struct CmagicConfigTests {
    @Test func parsesQuotedToken() {
        let toml = """
        # cmagic config
        token = "cm_abc123"
        """
        #expect(CmagicConfig.parseValue(for: "token", in: toml) == "cm_abc123")
    }

    @Test func ignoresCommentsAndTrailingComment() {
        let toml = """
        # token = "wrong"
        branch = main   # default branch
        """
        #expect(CmagicConfig.parseValue(for: "token", in: toml) == nil)
        #expect(CmagicConfig.parseValue(for: "branch", in: toml) == "main")
    }

    @Test func missingKeyReturnsNil() {
        #expect(CmagicConfig.parseValue(for: "token", in: "app = \"x\"") == nil)
    }
}
