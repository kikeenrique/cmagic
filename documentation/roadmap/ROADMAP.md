# Roadmap

Progress tracker for the Codemagic Swift CLI. The original vision is in
[`codemagic-swift-cli-brief.md`](./codemagic-swift-cli-brief.md); how the specs are produced and
the verification audit are in [`../PROCESS.md`](../PROCESS.md).

Legend: ✅ done · ⏳ pending · 🔑 blocked on a live `CM_TOKEN`.

## Status (August 2026)

**Phases 0–5 complete.** The `cmagic` CLI implements
the full command surface — `apps`, `builds`, `build show`/`show --steps`/`start`/`cancel`/`logs`,
`artifacts pull/public-url`, `caches list/delete` — each with `--json` output, all verified live
against a real token (`build start` verified live on 2026-07-15 via a start→cancel→show
round-trip that consumed no real build minutes). Both `artifacts` subcommands accept an optional
`--build-id` to target a specific build (instead of the latest build on a branch), fetched via the already-tested
`Codemagic.build(id:)`. The `CodemagicApiKit` library wraps a
swift-openapi-generator client (auth middleware + config-file token + artefact downloader). GitHub
Actions CI runs build + test. 28 offline tests, ~83% library line coverage (networked paths stubbed
with Replay). Released through `0.3.0` with prebuilt universal binaries; consumed by `mise` and a
separately-maintained Homebrew tap.

Every endpoint the CLI uses is live-confirmed, `instanceType` included, so no spec question is
outstanding (see PROCESS.md §5). `cmagic --version` reports the release the binary was built from.

**Remaining:** only the open questions below (revisit v3; preview-API stability).

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
      <version>` tags + pushes. `.github/workflows/release.yml` runs `mise run package` on a `v*`
      tag and attaches the assets via `gh release create` (SwiftPM cache in a release-scoped key
      that warm-starts from the CI dependency cache).
- [x] Cut the first release — tag `v0.1.0`, universal binaries published to the GitHub release.
- [x] Distribution consumers — `mise` via the `github:` backend
      (`mise use github:kikeenrique/cmagic`; prefer it over the deprecated `ubi:`, which forces a
      `v`-prefixed tag), and a **separately-maintained Homebrew tap** (`kikeenrique/homebrew-tap`)
      that packages `cmagic` on its own terms. The tap is outside this repo's scope — cmagic's
      responsibility ends at publishing `v`-prefixed tagged releases; downstream packaging consumes
      them.
- [x] CI (build + test) on the standalone repo — GitHub Actions (`.github/workflows/ci.yml`),
      `swift build` + `swift test` on `macos-26`/Xcode 26.6, with SwiftPM caching. Action versions
      kept current: `actions/checkout@v7`, `actions/cache@v6`, `jdx/mise-action@v4`.

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
