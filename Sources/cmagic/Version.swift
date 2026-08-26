/// The CLI's version, reported by `cmagic --version`.
///
/// Releases are cut from git tags, so this is the one place the number lives in the
/// tree: `mise run release v<x.y.z>` refuses to tag unless the two agree, which keeps
/// a published binary from reporting a stale version.
let cmagicVersion = "0.3.0-dev"
