# Roadmap

Progress tracker for the Codemagic Swift CLI. The original vision is in
[`codemagic-swift-cli-brief.md`](./codemagic-swift-cli-brief.md); how the specs are produced and
the verification audit are in [`../PROCESS.md`](../PROCESS.md).

Legend: ✅ done · ⏳ pending · 🔑 blocked on a live `CM_TOKEN`.

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

## Phase 0.5 — Close verification gaps 🔑

Blocked on a live `CM_TOKEN`. See PROCESS.md §5 "🔑 Needs a live token".

- [ ] Confirm `GET /apps` / `GET /apps/:id` response shapes
- [ ] Confirm `GET /builds` and `GET /builds/:id` exist and their shape; whether `?appId=` filters
- [ ] Confirm v1 build field names (`_id` vs `id`, `artifacts[].{url,name,type}`, `status` values)
- [ ] Confirm `POST /builds` accepts `instanceType`
- [ ] Tighten the `Build`/`Artifact` schemas in `openapi-v1.patch.json` from real responses

## Phase 1 — Package scaffolding & generated client ⏳

- [ ] `Package.swift`: package `cmagic` — `.library("CodemagicApiKit")` + `.executable("cmagic")`
- [ ] Add deps: `swift-openapi-generator` (plugin), `swift-openapi-runtime`, `swift-openapi-urlsession`
- [ ] Wire the generator against `documentation/openapi-v1.generated.json`
- [ ] `x-auth-token` injection middleware
- [ ] **Token from config file only** (see [Authentication](#authentication-decided) below)
- [ ] Hand-written `URLSession` artifact-download helper (bypasses the generator's `/`-in-path limit)

## Phase 2 — Core commands ⏳

- [ ] `cmagic apps` — list apps → `_id`
- [ ] `cmagic builds --app <id> [--branch <b>] [--limit N]`
- [ ] `cmagic build <buildId>` — one build's detail
- [ ] `cmagic artifacts pull --branch <b> --name <artifact> -o <dir>` — the core one-liner
      (resolve latest build for branch → match artifact by name → download → auto-unzip `.xcresult`/`.zip`)

## Phase 3 — Write ops & remaining surface ⏳

- [ ] `cmagic build start --app <id> --workflow <w> --branch <b>`
- [ ] `cmagic build cancel <buildId>`
- [ ] `cmagic artifacts public-url` (tokenless URL)
- [ ] `cmagic caches` list / delete

## Phase 4 — Polish & distribution ⏳

- [ ] `--json` output mode for every command (pipeable into `jq`)
- [ ] Tests: decode models against recorded JSON fixtures (no live network)
- [ ] `README.md` with install + `artifacts pull` example
- [ ] Distribute via `mise` (`spm:` backend or `ubi:` release binary) + a `mise run cmagic …` task
- [ ] CI (build + test) on the standalone repo

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
