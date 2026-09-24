# Roadmap

Progress tracker for the Codemagic Swift CLI. The original vision is in
[`codemagic-swift-cli-brief.md`](./codemagic-swift-cli-brief.md); how the specs are produced and
the verification audit are in [`../PROCESS.md`](../PROCESS.md).

Legend: ✅ done · ⏳ pending · 🔑 blocked on a live `CM_TOKEN`.

## Status (September 2026)

**Phases 0–6 complete; 0.4.0 released.** The `cmagic` CLI implements
the full command surface — `apps`, `builds`, `build show`/`show --steps`/`start`/`cancel`/`logs`,
`artifacts pull/public-url`, `caches list/delete` — each with `--json` output, all verified live
against a real token (`build start` verified live on 2026-07-15 via a start→cancel→show
round-trip that consumed no real build minutes). Both `artifacts` subcommands accept an optional
`--build-id` to target a specific build (instead of the latest build on a branch), fetched via the already-tested
`Codemagic.build(id:)`. The `CodemagicApiKit` library wraps a
swift-openapi-generator client (auth middleware + config-file token + artefact downloader). GitHub
Actions CI runs build + test on macOS and Linux. 28 offline tests, ~83% library line coverage
(networked paths stubbed with Replay). Released through `0.3.0` with prebuilt universal macOS
binaries; **0.4.0 adds Linux** — glibc and musl binaries for x86_64 and aarch64 — through a release
pipeline proven end to end on a published-then-deleted release candidate (Phase 6). Consumed by
`mise` and a separately-maintained Homebrew tap.

Every endpoint the CLI uses is live-confirmed, `instanceType` included, so no spec question is
outstanding (see PROCESS.md §5). `cmagic --version` reports the release the binary was built from.

**Remaining:** report the Linux download crash upstream, which nobody has yet been asked to fix;
retire two toolchain workarounds once upstream fixes ship (see [Pending](#pending-)); and the open
questions below (revisit v3; preview-API stability).

## Phase 0 — Research & API specs ✅

- [x] Initialize git repo + `.gitignore`
- [x] Commit the handoff brief
- [x] Analyse the API landscape (v1 vs v3) and decide to target **v1** (v1 has trigger/cancel/
      caches; v3 does not — see PROCESS.md §2)
- [x] Extract the official **v3** OpenAPI spec → `documentation/openapi-v3.json` (kept for reference)
- [x] Download the **v1** HTML docs → `documentation/v1-api-docs/*.html`
- [x] Write the docs→OpenAPI converter → `Scripts/GenerateOpenAPIV1.swift`
- [x] Author the enrichment overlay → `documentation/openapi-v1.patch.json`
- [x] Generate the v1 spec → `documentation/openapi-v1.generated.json` (13 operations)
- [x] Document the pipeline → `PROCESS.md`
- [x] Audit every claim against sources; fix assumptions (PROCESS.md §5)

## Phase 0.5 — Close verification gaps ✅

Verified live against a real token (July 2026, read endpoints only). See PROCESS.md §5.

- [x] Confirm `GET /apps` / `GET /apps/:id` response shapes (200; `_id`,`appName`,`workflowIds`,`branches`)
- [x] Confirm `GET /builds` and `GET /builds/:id` exist and their shape; `?appId=` filters (all 200; `nextPageUrl` paging)
- [x] Confirm v1 build field names (`_id` not `id`; artifact array is **`artefacts`**; `status` ∈ finished/failed/canceled/timeout)
- [x] Tighten the `Build`/`Artefact` schemas in `openapi-v1.patch.json` from real responses
- [x] Confirm `POST /builds` accepts `instanceType` — verified live 2026-08-26: `build start
      --instance-type mac_mini_m1` on a workflow defaulting to `mac_mini_m2` produced a build
      reporting `mac_mini_m1`, canceled before it started (no billable minutes)

## Phase 1 — Package scaffolding & generated client ✅

- [x] `Package.swift`: package `cmagic` — `.library("CodemagicApiKit")` + `.executable("cmagic")`
- [x] Add deps: `swift-openapi-generator` (plugin), `swift-openapi-runtime`, `swift-openapi-urlsession`, `swift-argument-parser`
- [x] Wire the generator against `Sources/CodemagicApiKit/openapi.json` (a copy of `documentation/openapi-v1.generated.json`); Artifacts tag filtered out
- [x] `x-auth-token` injection middleware (`AuthMiddleware`)
- [x] **Token from config file only** (`CmagicConfig`, see [Authentication](#authentication-decided) below)
- [x] Hand-written `URLSession` artefact-download helper (`ArtefactDownloader`; fetch `build.artefacts[].url` directly)
- [x] Verified end-to-end: `cmagic apps` lists apps live through the generated client

## Phase 2 — Core commands ✅

- [x] `cmagic apps` — list apps → `_id`
- [x] `cmagic builds --app <id> [--branch <b>] [--limit N]` (branch/limit are client-side — the v1
      API only filters by `appId`). Paging is the API's own: 30 builds per call, `--next-page <n>`
      sends its `skip` offset, and the resume offset comes back as a `next-page:` line
      (`--limit 0` walks to the end of the history; positional paging can repeat a build if one
      starts mid-walk — no stable cursor exists)
- [x] `cmagic build show <buildId>` — one build's detail (incl. artefacts + human sizes); `--steps`
      renders each build step's status + duration (v1 `buildActions`, verified live, 16 steps)
- [x] `cmagic artifacts pull [--app <id>] [--branch <b>] --name <substr> [-o <dir>]` — the core
      one-liner (latest build for branch → match artefact by name → download → auto-unzip zip/xcresult).
      Also accepts `--build-id <id>` to pull from a specific build (skips app/branch resolution).

All four verified live against the real token.

## Phase 3 — Write ops & remaining surface ✅

- [x] `cmagic build start --app <id> --workflow <w> (--branch <b> | --tag <t>)` — implemented and
      verified live 2026-07-15 (start→cancel→show round-trip against a real app; the build was
      canceled ~8s in, so no real build minutes were consumed)
- [x] `cmagic build cancel <buildId>` — verified live (208 → "already finished")
- [x] `cmagic artifacts public-url [--app] [--branch] --name <substr> [--expires-in-hours N]` —
      verified live (URLSession-direct; slash-path not generator-safe). Also accepts `--build-id <id>`
      to mint a URL for an artefact on a specific build (skips app/branch resolution).
- [x] `cmagic caches list|delete [--app] [--cache-id]` — list verified live; delete implemented (202)
- [x] `cmagic build logs <buildId> [--step N] [--raw]` — per-step logs via each step's `logUrl`
      (URLSession-direct; system steps carry `logUrl`, script steps carry it on their subaction);
      strips the `<span>` colour markup to plain text by default. Verified live.

## Phase 4 — Polish & distribution ✅

- [x] `--json` output mode for every command (pipeable into `jq`; verified live)
- [x] Tests (23, all offline; ~83% line coverage of CodemagicApiKit): config parsing + `load()`
      errors, model decoding (incl. `BuildAction` steps + subactions), `AuthMiddleware`, and the
      full networked layer (apps/builds/build/caches/cancel+208/start/public-url/download/step-log)
      via **Replay** synthetic stubs (no HAR, no private data). Replay is a test-only dependency.
      The `start`/`cancel` stubs were confirmed to match live API behaviour by the 2026-07-15
      round-trip, so no recorded (HAR) fixtures are needed for these write ops.
- [x] `README.md`: usage + `artifacts pull` example + `--json`/`jq` + **install** section
      (Homebrew + `mise` github backend)
- [x] Release automation — `mise/tasks/package` builds a universal (arm64+x86_64) binary via
      per-arch `swift build` + `lipo` (a single multi-arch build trips the XCBuild backend, which
      can't resolve the OpenAPI plugin), then packages it into **deterministic** tarballs (`gzip -n`,
      so both arch tarballs are byte-identical and share one sha256):
      `dist/cmagic-{aarch64,x86_64}-apple-darwin.tar.gz` + `SHA256SUMS`. `mise/tasks/release
      <version>` tags + pushes (re-runnable: it reuses a tag already on HEAD, so a failed push
      can be retried with the same command). `.github/workflows/release.yml` runs `mise run
      package` on a `v*`
      tag and attaches the assets, creating the release or refreshing an existing one's assets so
      a re-pushed tag re-runs cleanly (SwiftPM cache in a release-scoped key
      that warm-starts from the CI dependency cache). Extended to Linux in Phase 6.
- [x] Cut the first release — tag `v0.1.0`, universal binaries published to the GitHub release.
- [x] Distribution consumers — `mise` via the `github:` backend
      (`mise use github:kikeenrique/cmagic`; prefer it over the deprecated `ubi:`, which forces a
      `v`-prefixed tag), and a **separately-maintained Homebrew tap** (`kikeenrique/homebrew-tap`)
      that packages `cmagic` on its own terms. The tap is outside this repo's scope — cmagic's
      responsibility ends at publishing `v`-prefixed tagged releases; downstream packaging consumes
      them.
- [x] CI (build + test) on the standalone repo — GitHub Actions (`.github/workflows/ci.yml`),
      `swift build` + `swift test` on `macos-26`/Xcode 26.6, with SwiftPM caching. Action versions
      kept current: `actions/checkout@v7`, `actions/cache@v6`, `jdx/mise-action@v4`. A Linux job
      and newer artifact actions were added in Phase 6.

Repo public, default branch `main`. cmagic publishes `v`-prefixed tagged releases with prebuilt
universal binaries; downstream packaging (a separate Homebrew tap, `mise`) consumes them.

## Phase 5 — Paging & version reporting ✅

August 2026. Prompted by `cmagic builds --limit 300` returning 30 builds.

- [x] Page `GET /builds` — the API serves 30 per call and its `nextPageUrl` cursor is
      `?appId=<id>&skip=<n>`, which honours arbitrary offsets, so paging is server-side:
      `--limit` walks the cursor (`0` = the whole history), `--next-page <n>` starts `n` builds in,
      and the offset to resume from comes back as a `next-page:` line / `nextPage` in `--json`,
      counted from the rows shown so chained calls neither skip nor repeat a build. `--max-pages`
      (default 20) bounds a walk — it only bites with `--branch`, still client-side since the API
      filters by app only. Verified live: `--limit 25` + `--next-page 25` reassembles exactly into
      `--limit 35`.
- [x] Establish there is **no page-size parameter** — `limit`, `perPage`, `per_page`, `pageSize`,
      `count`, `take` were each sent live and ignored (30 builds every time)
- [x] `build start --instance-type <t>` — added to the spec overlay and confirmed live 2026-08-26
      (a build requested as `mac_mini_m1` on a workflow defaulting to `mac_mini_m2` reported
      `mac_mini_m1`; canceled before it started, no billable minutes)
- [x] `cmagic --version` — reports `cmagicVersion` (`Sources/cmagic/Version.swift`), the one place
      the number lives in the tree. Releases are still cut from tags, so `mise run release` refuses
      to tag while the tag and the constant disagree, keeping a published binary from reporting a
      stale version.
- [x] Docs kept in step — README usage/paging/layout, PROCESS.md §5 (live findings, nothing left
      unverified), this roadmap
- [x] Cut `0.3.0` — `cmagicVersion` bumped, tagged `v0.3.0`. **Breaking:** `builds --json` now
      emits `{builds, nextPage}` instead of a bare array, so `jq '.[]'` pipelines become
      `jq '.builds[]'`

## Phase 6 — Linux support & multi-platform release ✅

September 2026. Every Linux path below was first proven in CI, and most were first *broken* there —
the entries record what each failure taught.

- [x] **Linux source compatibility.** `Codemagic.swift` now imports `FoundationNetworking`: on Linux,
      Foundation vends a `typealias URLSession = AnyObject` placeholder, so the stored session
      silently took the stub and every call site failed to compile. `artifacts pull` resolves
      `unzip` off `PATH` instead of hard-coding `/usr/bin/unzip`, and keeps the archive with a clear
      error when it is missing.
- [x] **CI on Linux** — `swift build` + `swift test` in a `swift:6.4-noble` container. All 28 tests
      pass there except `downloadsArtefactToFile`, skipped on corelibs Foundation: its
      `URLSession.download(for:)` force-unwraps a nil file URL when a stubbed `URLProtocol` delivers
      bytes rather than a file (a hard crash, so no expected-failure trait can express it). An
      analysis with the stack trace and a reproduction was written up for reporting upstream; no
      issue has been filed yet (see Pending).
- [x] **Dependencies raised to current releases**, with the floors now explicit in `Package.swift`
      rather than only in the lockfile (Replay 0.6.0, swift-openapi-generator 1.13.1,
      swift-openapi-runtime 1.12.1, …).
- [x] **Two Linux variants, x86_64 + aarch64 each**, named by full target triple
      (`-unknown-linux-gnu`, `-unknown-linux-musl`) — the prevailing convention, and free:
      `ubi` only filters on libc when the *host* is musl, and `mise` scores rather than filters.
  - `package-linux-gnu` — the conventional primary artefact. Built on **RHEL UBI 9** for the
    lowest glibc floor that links, **2.34** (measured across five images: ubi9 2.34, jammy 2.35,
    bookworm 2.36, noble 2.39, resolute 2.43). The Swift runtime is static, but libcurl, libstdc++
    and libgcc_s come from the host. aarch64 builds on a native arm64 runner.
  - `package-linux-musl` — fully static via the Static Linux SDK, no dependencies at all; one
    x86_64 runner emits both arches.
  - `--static-swift-stdlib` needed a workaround. Swift 6.4's default backend, Swift Build, compiles
    against the *dynamic* resource directory, so the objects never request CoreFoundation, ICU and
    the rest ([swiftlang/swift-build#1764]). Passing `-Xswiftc -static-stdlib` reproduces the
    upstream fix ([#1763]) while staying on the supported backend — the deprecated
    `--build-system native` also linked, but would tie the build to the past.
- [x] **`smoke-test` task** — unpacks a tarball, runs it, and drives a real request with a
      throwaway token: reaching the server for a 401 proves the TLS handshake and certificate
      validation work, which matters because the static builds carry their own TLS stack.
- [x] **Release workflow restructured** — macOS, glibc matrix and musl builders feed a publish job
      that merges per-job checksum fragments into one `SHA256SUMS`. A manual dispatch is a **dry
      run** that publishes nothing; a suffixed tag publishes as a **prerelease**, so it never shows
      as "latest" to installers.
- [x] **CI modernised** — `upload-artifact@v7`, `download-artifact@v8`, runners on
      `ubuntu-26.04` / `ubuntu-26.04-arm` ahead of `ubuntu-latest`'s migration to 26.04
      (19 Oct – 19 Nov 2026). The containers carry the build; the host only boots them.
- [x] **Pipeline proven end to end** — dry runs, then a real `v0.3.1-rc1`: published as a
      prerelease with seven assets, checksums verified against the downloads, the macOS binary run
      on a real Mac, `releases/latest` left on `v0.3.0`, a `gh run rerun` exercising the
      `--clobber` refresh (checksums re-verified against GitHub's own digests), then deleted.
- [x] **Docs** — the README trimmed to a user-facing intro (what cmagic does, install with an
      asset table, Linux notes, getting started); build, layout, spec regeneration and the new
      release process moved to [`DEVELOPMENT.md`](../DEVELOPMENT.md); PROCESS.md §7.
- [x] **Released `0.4.0`** (2026-09-23) — `cmagicVersion` bumped, tagged `v0.4.0`. Verified on the
      published release: seven assets, not a prerelease, `releases/latest` now `v0.4.0` so installers
      pick it up, every checksum matching GitHub's own digest, and the macOS binary reporting `0.4.0`.
      The repo is also now MIT-licensed.

## Phase 7 — Release size ✅

September 2026, after 0.4.0. The 0.4.0 Linux binaries shipped unstripped: the musl download was
54.8 MB, ~17× the macOS one, because the Static Linux SDK's prebuilt static libraries (Foundation,
ICU, curl, BoringSSL) carry their DWARF and full static linking pulled all 87 MB of it in.

- [x] **Link the Linux binaries with `-Xlinker --strip-debug`** — drops DWARF, keeps the symbol
      table: the same shape as the macOS binary (~27,000 symbols, no embedded debug info, since
      Mach-O keeps DWARF in dSYMs), and it keeps function names in Swift crash backtraces.
      Stripping everything would save ~2.7 MB more per build and leave backtraces as bare
      addresses. Linker-time rather than a post-build `objcopy`, so the aarch64 musl slice needs
      no cross-arch tool on the x86_64 runner. Verified by a Release dry run, measured on its
      artefacts:

      | tar.gz | 0.4.0 | stripped |
      |---|---|---|
      | musl x86_64 / aarch64 | 55.0 / 53.7 MB | **25.7 / 25.3 MB** (−53%) |
      | glibc x86_64 / aarch64 | 25.9 / 25.5 MB | 24.0 / 23.6 MB (−7%) |

      All four binaries have zero `.debug_*` sections and keep 150–250k symbols; smoke tests pass.
      Stripping cannot reach macOS size — both Linux builds carry ~35 MB of `.rodata`, Foundation
      and the ICU data, that macOS takes from the OS — but musl's penalty against glibc drops from
      2.1× to ~7%.
- [x] **Guard against regression** — each Linux task fails if `.debug_info` survives the link, and
      always reports what it did: a pass names the binary, and a skip (no `readelf`) raises a
      GitHub Actions warning, so a skipped check can't pass for a clean one. Confirmed active in
      both the UBI 9 and noble images — it checked all four binaries with `readelf`.
- [x] **Released `0.4.1`** (2026-09-23) — verified on the published release: seven assets, not a
      prerelease, `releases/latest` now `v0.4.1`, every checksum matching GitHub's own digest, the
      Linux tarballs at their stripped sizes, and the macOS binary reporting `0.4.1`.

## Phase 8 — Verifiable checksums ✅

September 2026. Every `SHA256SUMS` from v0.1.0 to v0.4.1 listed its assets under the build path —
`<hash>  dist/cmagic-….tar.gz` — so a user running `sha256sum -c SHA256SUMS` in their download
folder had every line fail, even for files sitting right there. The release pipeline never
noticed, because nothing checked the file from a user's point of view. Homebrew (a hash per asset
in the formula) and mise (which doesn't read published checksum files) were unaffected.

- [x] **Bare file names** — the three package tasks hash from inside `dist/`.
- [x] **Check it as a user would** — the publish job runs `sha256sum --strict -c SHA256SUMS` from
      inside the folder holding the assets, before anything is published.
- [x] **Documented** — the README gives the verify command for macOS and Linux, with
      `--ignore-missing` so one downloaded file can be checked on its own.
- [x] **Past releases corrected** (2026-09-24) — each release's `SHA256SUMS` re-uploaded with the
      prefix removed, one release at a time: v0.1.0, v0.2.0, v0.3.0, v0.4.0, v0.4.1. Each corrected
      file was checked against GitHub's own digest for every asset before upload, and after it the
      published file was byte-identical, the tarballs untouched, and a real download verified `OK`
      in a plain folder. The hashes themselves never changed, so nothing pinning a tarball was
      affected. The originals are kept outside the repo in case the change needs reverting.
- [x] **Released `0.4.2`** (2026-09-24) — the first release built with bare-name checksums and
      the user-side check. Verified on the published release: seven assets, not a prerelease,
      `releases/latest` now `v0.4.2`, every checksum matching GitHub's own digest, a real download
      verifying `OK` in a plain folder, and the macOS binary reporting `0.4.2`.

## Pending ⏳

- [ ] **Drop `-Xswiftc -static-stdlib`** from `package-linux-gnu` once a released toolchain carries
      [#1763]. As of 2026-09-23 the backport to the `release/6.4.x` branch (#1770) has merged, while
      those to `release/6.4.1` (#1772) and `release/6.4.2` (#1771) are still open, and Docker Hub
      has no Swift image newer than `6.4.0`. Whichever 6.4 point release ships first with it,
      move the `swift:6.4-*` container tags and the Static Linux SDK pin together — the SDK only
      works with its own toolchain version — then drop the flag and dry-run to confirm.
- [ ] **Report the Linux download crash upstream.** Nobody has been asked to fix it: there is no
      issue in Replay or in swift-corelibs-foundation. Two defensible targets, and it is worth
      filing both — corelibs, because `download(for:)` force-unwraps a condition any third-party
      `URLProtocol` can produce (`URLSession.swift:849`, and `:875` for `download(from:)`), where it
      should throw; and Replay, where `PlaybackURLProtocol` could write the body to a temporary
      file for download tasks. The written-up analysis has the stack trace and a reproduction.
- [ ] **Re-enable `downloadsArtefactToFile` on Linux** once either fix lands. The skip hides
      coverage and nothing reports when it becomes unnecessary, so re-check on each Foundation or
      Replay bump.
- [ ] *Optional:* smoke-test the aarch64 musl binary, the one artefact that ships unexercised —
      it needs qemu, or a native arm64 job with the Static Linux SDK installed.

Downstream, outside this repo: the Homebrew tap needs `on_linux` blocks to serve the new assets.
The tap is maintained separately and consumes the published releases on its own terms.

[swiftlang/swift-build#1764]: https://github.com/swiftlang/swift-build/issues/1764
[#1763]: https://github.com/swiftlang/swift-build/pull/1763

## Authentication (decided)

The API token is read from a **config file only** — no `--token` flag, no `CM_TOKEN` env var, no
Keychain (kept simple; can be revisited later).

- **Path:** `$XDG_CONFIG_HOME/cmagic/config.toml`, falling back to
  `~/.config/cmagic/config.toml`.
- **Format (TOML):**
  ```toml
  token = "cm_xxxxxxxx"
  # optional future defaults:
  # app = "664..."
  # branch = "main"
  ```
- **Permissions:** the file should be `chmod 600`; the CLI warns if it is group/world-readable.
- **Missing/empty token:** fail with a clear message naming the expected path. Never log the token.

## Open questions

- Revisit v3: worth generating a second client for its accurate read models, or stay v1-only?
- Are the "preview" build APIs stable enough to depend on? (v1 docs warn they may change.)
