# Handoff Brief — Codemagic Swift CLI package

**Audience:** an agent starting fresh in a new, empty repo. This is self-contained — you do not
need the originating project to act on it.

## 1. What we're building & why

A **Swift CLI + library** that talks to the **Codemagic REST API** to inspect builds and download
their artifacts from the terminal. It exists because Codemagic ships **no official CLI for accessing
builds/artifacts/logs** — the official `codemagic-cli-tools` (Python) only runs build/codesign/deploy
steps *inside* the CI VM; it cannot query the service. The only remote-access route today is raw
`curl` against `api.codemagic.io`. This package replaces that with a typed Swift client.

**Immediate motivating use case:** when a CI build goes red, pull that build's
`TestResults-<suite>.xcresult` (and/or raw `xcodebuild*.log`) artifact locally to diagnose it —
instead of downloading by hand from the Codemagic web UI.

## 2. Decision (already made)

- **Home:** its own **standalone repo** (not inside the consuming app repo). Rationale: the client is
  100% generic (nothing app-specific in the code — only invocation args are), has reuse / possible
  OSS value, and there is no good Swift Codemagic client in the wild.
- **Consumption:** the consuming app pulls it in via **`mise`** (an `spm:` backend entry, or a
  `ubi:` GitHub-release binary), wrapped in a `mise run cm …` task. The app repo stays dependency-clean.
- **Split:** a reusable **`CodemagicKit`** library + a thin **`codemagic`** executable, so the client
  is importable independent of the CLI front-end.

## 3. Codemagic REST API reference (verified July 2026)

- **Base URL:** `https://api.codemagic.io`  (stable v1; note Codemagic is transitioning to a newer
  API at `https://codemagic.io/api/v3/schema` — target v1 unless v3 is clearly better on inspection.)
- **Auth:** header `x-auth-token: <TOKEN>` on every request. Token generated in the Codemagic UI at
  **Account settings → API token**. Read it from the `CM_TOKEN` env var; never hard-code or commit it.

| Purpose | Method + path | Notes |
|---|---|---|
| List applications | `GET /apps` | Each app id is the `_id` field (also `appName`, `workflowIds`) |
| List / filter builds | `GET /builds` | Returns build objects incl. `status`, `branch`, `workflowId`, and an **`artifacts`** array (each entry has a `url`, name, type). Filter by app id. |
| Get one build | `GET /builds/:id` | Same object shape, single build |
| Start a build | `POST /builds` | body: `appId`, `workflowId`, `branch`\|`tag` (one required); optional `environment`, `labels`, `instanceType` → returns `buildId` |
| Cancel a build | `POST /builds/:id/cancel` | `208 Already Reported` if already finished |
| Download an artifact | `GET /artifacts/:secureFilename` | `secureFilename` = the `url` from a build's `artifacts[]`. Form: `/artifacts/<build-id>/<artifact-id>/<filename>` |
| Public (tokenless) URL | `POST /artifacts/:secureFilename/public-url` | body `{"expiresAt": <unix-seconds>}` → `{url, expiresAt}`. Anyone with the URL can download — use sparingly. |

**No documented raw-log endpoint** exists — logs are a UI feature. In practice a CI config can
publish its logs *as artifacts* (this project publishes both `.xcresult` bundles and `xcodebuild*.log`),
so log access is just artifact download.

### Reference `curl` flow (what the CLI automates)

```bash
export CM_TOKEN=…
BASE=https://api.codemagic.io
curl -s -H "x-auth-token: $CM_TOKEN" $BASE/apps \
  | jq '.applications[] | {_id, appName}'
curl -s -H "x-auth-token: $CM_TOKEN" "$BASE/builds?appId=<APP_ID>" \
  | jq '.builds[] | {_id, status, branch, artifacts: [.artifacts[].url]}'
curl -s -H "x-auth-token: $CM_TOKEN" -o out.zip "<artifact url>"
```

## 4. Proposed package layout

```
<repo>/
  Package.swift                 # products: .library("CodemagicKit"), .executable("codemagic")
  Sources/
    CodemagicKit/               # reusable async client
      Client.swift              # base URL, x-auth-token injection, request/decoding plumbing
      Models/                   # App, Build, Artifact — Codable, Sendable
      Endpoints/                # apps, builds(list/get), artifacts(list/download/public-url), build(start/cancel)
    codemagic/                  # CLI front-end (thin over CodemagicKit)
      Commands/                 # apps, builds, build, artifacts, start, cancel
  Tests/CodemagicKitTests/      # decode against recorded JSON fixtures (no live network)
  README.md
```

## 5. Command surface (v1)

```
codemagic apps                                          # list apps → _id
codemagic builds --app <id> [--branch <b>] [--limit N]  # recent builds: id, status, branch, artifacts
codemagic build <buildId>                               # one build's detail
codemagic artifacts pull --branch <b> \                 # ← the core one-liner
        --name TestResults-Accessibility.xcresult -o ./out/
codemagic build start --app <id> --workflow <w> --branch <b>
codemagic build cancel <buildId>
```

`artifacts pull` = resolve latest build for `--branch` → match an artifact by `--name` → download,
and auto-unzip when the artifact is a `.xcresult`/`.zip`.

## 6. Conventions / constraints

- **Swift 6, strict concurrency (`complete`).** Client types `Sendable`; use `async/await` +
  `URLSession`. No callback APIs.
- **Only dependency:** `swift-argument-parser` for the CLI. Keep `CodemagicKit` dependency-free
  (Foundation only) so it stays cheap to embed.
- **Config precedence for the token:** `--token` flag > `CM_TOKEN` env > optional config file.
  Fail with a clear message if none is set; never log the token.
- **Errors:** surface HTTP status + Codemagic error body; distinguish auth (401/403) from not-found.
- **Testing:** unit-test model decoding against saved JSON fixtures; do not hit the network in tests.
- **Output:** human-readable table by default; add `--json` for machine consumption (so CI scripts
  can pipe into `jq`).

## 7. First milestone (thin vertical slice)

1. `Package.swift` with the two products + `swift-argument-parser`.
2. `Client` with `x-auth-token` + generic `GET`/`POST` JSON.
3. `GET /apps` and `GET /builds` decoded into models.
4. `codemagic apps` and `codemagic artifacts pull` working end-to-end against a real token.
5. README with install (`mise use spm:<owner>/<repo>`) + the `artifacts pull` example.

Everything after that (start/cancel, public-url, `--json`, config file) is incremental.
