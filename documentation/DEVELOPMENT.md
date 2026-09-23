# Development

How to build, test and release cmagic, and how the codebase fits together. For what cmagic is and
how to use it, see the [README](../README.md). Two companion documents go deeper:
[`PROCESS.md`](./PROCESS.md) covers the API research and how the OpenAPI spec is produced, and
[`roadmap/ROADMAP.md`](./roadmap/ROADMAP.md) tracks what is done and what is pending.

## Build, test, run

```bash
swift build            # or: mise run build
swift test             # or: mise run test
swift run cmagic --help
```

Both work on macOS and Linux with a Swift 6 toolchain; CI runs them on each. On Linux one test,
`downloadsArtefactToFile`, is skipped: corelibs Foundation's `URLSession.download(for:)` crashes
when the response comes from a stubbed `URLProtocol`, so the stub-driven test cannot run there.
The comment on the test records the stack trace and when to re-enable it.

The tests are all offline. The networked layer is exercised against synthetic
[Replay](https://github.com/mattt/Replay) stubs — no recorded traffic, no private data.

## Approach

The client is generated with Apple's [swift-openapi-generator] rather than hand-written. We target
the **v1** API (`https://api.codemagic.io`) because it has the operations we need — trigger, cancel,
artifacts, caches — which the newer v3 API does not yet expose. Codemagic publishes no
machine-readable spec for v1, so we build one from its HTML docs (see below). The official **v3**
spec is kept for reference.

A few endpoints can't go through the generated client — the artefact path is a multi-segment
parameter the generator would percent-encode — so those are small hand-written `URLSession`
helpers: artefact download, public URLs and step logs. [`PROCESS.md`](./PROCESS.md) §5 explains why.

## Repository layout

```
Package.swift
mise.toml                        # build/test tasks; includes mise/tasks/
mise/tasks/
  package                        # macOS universal binary → dist/ (lipo of per-arch builds)
  package-linux-gnu              # Linux glibc binary for the host arch (static Swift runtime)
  package-linux-musl             # Linux musl binaries, both arches (Static Linux SDK)
  smoke-test                     # unpack a tarball; check it runs and reaches the API over TLS
  release                        # tag + push, refusing if the tag and cmagicVersion disagree
.github/workflows/
  ci.yml                         # build + test on macOS and Linux
  release.yml                    # build, smoke-test and publish; manual dispatch = dry run
Sources/
  CodemagicApiKit/               # library: generated OpenAPI client + auth + config + artefact download
    openapi.json                 # spec fed to the generator (copy of documentation/openapi-v1.generated.json)
    openapi-generator-config.yaml
    Codemagic.swift              # client wrapper (base URL + auth middleware)
    Codemagic+Convenience.swift  # model-returning API: apps/builds/caches/cancel/start/…
    BuildPaging.swift            # GET /builds paging — skip offsets off the nextPageUrl cursor
    AuthMiddleware.swift         # injects x-auth-token
    Configuration.swift          # CmagicConfig — loads token from the config file
    ArtefactDownloader.swift     # URLSession download of build.artefacts[].url
    PublicURL.swift              # URLSession-direct artefact public-url helper
    StepLogs.swift               # URLSession-direct per-step build-log fetch
  cmagic/                        # executable (thin ArgumentParser front-end)
    Cmagic.swift                 # root + apps/builds/build(show/start/cancel/logs)
    Version.swift                # cmagicVersion — what `cmagic --version` reports
    ArtifactsCommand.swift       # artifacts pull/public-url + unzip
    CachesCommand.swift          # caches list/delete
    OutputOptions.swift          # shared --json flag + emitter
Tests/CodemagicApiKitTests/      # 28 offline tests (config, decoding, auth, Replay stubs); 1 skipped on Linux
Scripts/
  GenerateOpenAPIV1.swift        # scrapes the v1 HTML docs → OpenAPI, merging a hand-authored patch
documentation/
  DEVELOPMENT.md                 # this document
  PROCESS.md                     # how the specs are produced + the verification audit (§5)
  openapi-v1.generated.json      # the v1 spec we feed the generator (scrape + patch) — do not hand-edit
  openapi-v1.patch.json          # hand-authored overlay: endpoints/schemas the v1 docs omit
  openapi-v3.json                # official v3 OpenAPI spec (reference only)
  v1-api-docs/                   # downloaded v1 REST API docs (the scraper's input)
  roadmap/
    codemagic-swift-cli-brief.md # original handoff brief / vision
    ROADMAP.md                   # achieved + pending tasks
```

## Regenerating the OpenAPI specs

```bash
# v3 (official, published)
curl -sSL -o documentation/openapi-v3.json https://codemagic.io/api/v3/schema/openapi.json

# v1 (scraped from docs, then patch-merged)
DIR=documentation/v1-api-docs
for slug in codemagic-rest-api applications builds artifacts caches; do
  curl -sSL -o "$DIR/$slug.html" "https://docs.codemagic.io/rest-api/$slug/"
done
swift Scripts/GenerateOpenAPIV1.swift
```

To change the v1 spec, edit the docs (re-scrape) or `documentation/openapi-v1.patch.json`
(enrichment) and re-run the script — never hand-edit the generated file. Then copy the result over
`Sources/CodemagicApiKit/openapi.json`, which is what the generator plugin reads. Full details in
[`PROCESS.md`](./PROCESS.md).

## Releasing

Releases are cut from `v`-prefixed git tags and built by
[`.github/workflows/release.yml`](../.github/workflows/release.yml): four parallel builders
(macOS, Linux glibc on x86_64 and aarch64, Linux musl for both arches) and a publish job that
merges their checksums and attaches everything to the GitHub release. Each Linux binary that can
run on its builder is smoke-tested first — it must reach the Codemagic API over TLS — or nothing
is published.

```bash
gh workflow run Release              # dry run: builds + smoke-tests everything, publishes nothing
mise run release v0.4.0              # the real thing: tags HEAD and pushes the tag
```

- **Dry-run first.** A manual dispatch runs the whole pipeline but stops short of publishing; its
  `dry-run-dist` workflow artefact holds exactly what the release would carry. Only a tag publishes.
- **Bump the version before tagging.** `mise run release` refuses to tag unless the tag matches
  `cmagicVersion` in `Sources/cmagic/Version.swift`, so a binary never reports the wrong version.
- **Suffixed tags are prereleases.** `v0.4.1-rc1` publishes with `--prerelease`, which keeps it out
  of GitHub's "latest release" and so away from installers — a safe way to rehearse a release.
- **Re-running is safe.** Re-running a tag's workflow run (`gh run rerun <id>`) refreshes the
  existing release's assets instead of failing, and `mise run release` reuses a tag already on HEAD,
  so a failed push can be retried with the same command.

The packaging lives in `mise` tasks so a human and CI run the same thing: `mise run package`
(macOS), `package-linux-gnu`, `package-linux-musl` and `smoke-test`. The two Linux ones need a
swift.org toolchain and run in CI; see each task's header for why.

Downstream packaging — the separately-maintained Homebrew tap, and `mise` — consumes the published
releases on its own terms; this repo's responsibility ends at publishing them.

[swift-openapi-generator]: https://github.com/apple/swift-openapi-generator
