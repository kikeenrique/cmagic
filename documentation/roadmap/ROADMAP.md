# Roadmap

Progress tracker for the Codemagic Swift CLI. The original vision is in
[`codemagic-swift-cli-brief.md`](./codemagic-swift-cli-brief.md); how the specs are produced and
the verification audit are in [`../PROCESS.md`](../PROCESS.md).

Legend: ✅ done · ⏳ pending · 🔑 blocked on a live `CM_TOKEN`.

## Status (July 2026)

**Phases 0–3 complete; Phase 4 in progress.** The `cmagic` CLI implements the full command surface
— `apps`, `builds`, `build show/start/cancel`, `artifacts pull/public-url`, `caches list/delete` —
each with `--json` output, all verified live against a real token (except `build start`, which
would trigger a real build). The `CodemagicApiKit` library wraps a swift-openapi-generator client
(auth middleware + config-file token + artefact downloader). 21 offline tests, ~83% library line
coverage (networked paths stubbed with Replay).

**Remaining:** a README install section, `mise` distribution, and CI — all in Phase 4 below.

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
- [ ] Confirm `POST /builds` accepts `instanceType` (deferred — would trigger a real build)

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
      API only filters by `appId`; first page only for now)
- [x] `cmagic build show <buildId>` — one build's detail (incl. artefacts + human sizes)
- [x] `cmagic artifacts pull [--app <id>] [--branch <b>] --name <substr> [-o <dir>]` — the core
      one-liner (latest build for branch → match artefact by name → download → auto-unzip zip/xcresult)

All four verified live against the real token.

## Phase 3 — Write ops & remaining surface ✅

- [x] `cmagic build start --app <id> --workflow <w> (--branch <b> | --tag <t>)` — implemented
      (not run live — triggers a real build)
- [x] `cmagic build cancel <buildId>` — verified live (208 → "already finished")
- [x] `cmagic artifacts public-url [--app] [--branch] --name <substr> [--expires-in-hours N]` —
      verified live (URLSession-direct; slash-path not generator-safe)
- [x] `cmagic caches list|delete [--app] [--cache-id]` — list verified live; delete implemented (202)

## Phase 4 — Polish & distribution ⏳

- [x] `--json` output mode for every command (pipeable into `jq`; verified live)
- [x] Tests (21, all offline; ~83% line coverage of CodemagicApiKit): config parsing + `load()`
      errors, model decoding, `AuthMiddleware`, and the full networked layer (apps/builds/build/
      caches/cancel+208/start/public-url/download) via **Replay** synthetic stubs (no HAR, no
      private data). Replay is a test-only dependency.
- [~] `README.md`: usage + `artifacts pull` example + `--json`/`jq` done; **install** section
      still pending (needs distribution below)
- [ ] Distribute via `mise` (`spm:` backend or `ubi:` release binary) + a `mise run cmagic …` task
- [ ] CI (build + test) on the standalone repo

Blocked on a decision: the eventual GitHub **owner/repo** (needed for `mise use spm:<owner>/<repo>`
and `ubi:` release binaries).

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
