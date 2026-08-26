# Process — Codemagic API research & OpenAPI pipeline

This document records how we analysed the Codemagic REST API and how we produce the
OpenAPI spec(s) that drive client generation. It is meant to be reproducible: anyone
should be able to re-run the steps and get the same artifacts.

## 1. Goal

Build a Swift client for the Codemagic REST API, and generate as much of it as possible
with Apple's [swift-openapi-generator] rather than hand-writing models. That requires a
machine-readable OpenAPI document. This doc explains which API we target and how the
spec is obtained.

## 2. API landscape (investigated July 2026)

Codemagic exposes **two** REST APIs and is mid-transition between them (the v1 docs carry
a banner: *"We are transitioning to our new API"*, pointing at the v3 schema).

| | v1 | v3 |
|---|---|---|
| Base URL | `https://api.codemagic.io` | `https://codemagic.io/api/v3` |
| Auth | header `x-auth-token` | header `x-auth-token` (same token) |
| Spec | **none published** (HTML docs only) | **OpenAPI 3.1.0**, published |
| Focus | apps, builds, artifacts, caches | teams / billing / OTA / previews / secrets; read-only builds |
| Trigger build (`POST /builds`) | ✅ | ❌ not implemented |
| Cancel build | ✅ | ❌ |
| Artifact download | ✅ (`/artifacts/:secureFilename`) | ✅ via build's `artifacts[].short_lived_download_url` |
| Caches | ✅ | ❌ |
| Build listing filter | by `appId` | by `team_id` |

**Note on the v3 overview blurb.** The v3 spec's `info.description` says the platform lets you
"manage your apps, trigger builds, access artifacts, and more." That is aspirational platform
copy — the v3 *endpoint surface* does not yet include build triggering or a dedicated artifacts
route. "Access artifacts" is satisfied indirectly through `short_lived_download_url` on the
build object.

### Getting the v3 spec out of the Safari webarchive

The v3 docs page (`https://codemagic.io/api/v3/schema`) renders with **Scalar**, which loads the
spec via XHR from `data-url="/api/v3/schema/openapi.json"`. A Safari `.webarchive` captures the
rendered DOM and static subresources but **not** that XHR response, so the raw spec is not inside
`documentation/Codemagic-API.webarchive`. We confirmed this by parsing the webarchive
(binary plist → 16 resources) and finding only the Scalar library + rendered HTML. The real spec
was fetched directly:

```bash
curl -sSL -o documentation/openapi-v3.json https://codemagic.io/api/v3/schema/openapi.json
# => OpenAPI 3.1.0, "Codemagic API v3.0", 64 paths, 212 schemas
```

## 3. Decision — target v1, generated from its docs

The motivating use case (pull a red build's `.xcresult`, optionally trigger/cancel builds) needs
**trigger + cancel + caches**, which only exist in **v1**. v3 is kept around
for its accurate read models and possible future use (`openapi-v3.json`), but the client is built against **v1**.

Since v1 has no published spec, we generate one **from its own HTML documentation**, so the spec
stays traceable to an authoritative source and can be regenerated when the docs change.

## 4. The v1 docs → OpenAPI pipeline

### Step 1 — download the docs

```bash
DIR=documentation/v1-api-docs
mkdir -p "$DIR"
for slug in codemagic-rest-api applications builds artifacts caches; do
  curl -sSL -o "$DIR/$slug.html" "https://docs.codemagic.io/rest-api/$slug/"
done
```

The pages are server-rendered HTML with a regular shape per operation:
`<h2>Summary</h2>` → `<code>METHOD /path</code>` → optional `<table>` of parameters.

### Step 2 — convert to OpenAPI

```bash
swift Scripts/GenerateOpenAPIV1.swift            # uses the defaults below
# or explicitly:
swift Scripts/GenerateOpenAPIV1.swift documentation/v1-api-docs \
      documentation/openapi-v1.generated.json documentation/openapi-v1.patch.json
```

The script (Foundation-only, no dependencies) extracts, per operation:

- **method + path** (`:id` → `{id}`),
- **summary** (the `<h2>` heading),
- **parameters** (the Parameters table): path params from the URL, the rest become query params
  (GET/DELETE) or `requestBody` JSON properties (POST/PUT/PATCH), with type + required flag.

It sets sensible response codes it cannot infer from prose: `200` generic for reads/writes,
`202` for DELETE (async), and an extra `208` on `/builds/:id/cancel`.

### Step 3 — merge the patch (happens automatically inside the script)

The v1 HTML docs are incomplete, so after scraping, the script **deep-merges** a hand-authored
overlay — **`documentation/openapi-v1.patch.json`** — into the result. Merge rule: dictionaries
merge recursively; on any leaf or array the patch wins. Keys prefixed with `_` (comments) are
ignored.

The patch supplies what the docs omit:

- the **undocumented-but-real** `GET /builds` and `GET /builds/:id` (needed to list/inspect
  builds — the v1 docs describe neither),
- the shared `Build` / `Artifact` response schemas those endpoints reference.

Output: **`documentation/openapi-v1.generated.json`** — 11 scraped operations + 2 patched =
13 operations across Applications / Builds / Artifacts / Caches. This single file is what we feed
to swift-openapi-generator.

**Never hand-edit the generated file.** To change the spec, edit either the docs (re-scrape) or
`openapi-v1.patch.json` (enrichment), then re-run the script. Re-scraping is also how we detect
when Codemagic's docs drift.

## 5. Verification (July 2026)

Every factual claim in this doc and in `roadmap/codemagic-swift-cli-brief.md` was audited against
primary sources: the downloaded v1 docs (`v1-api-docs/*.html`), the extracted v3 spec
(`openapi-v3.json`), the codemagic-cli-tools repo, and — as of July 2026 — **live API calls with a
real token** (read endpoints only; no build was triggered). Legend: ✅ confirmed · ⚠️ corrected.

### ✅ Confirmed

| Claim | Evidence |
|---|---|
| v1 base URL `https://api.codemagic.io`; auth header `x-auth-token` | curl examples throughout v1 docs (12× `x-auth-token`) |
| v1 token location "Account settings > API token" | applications overview |
| `POST /builds` params: `appId`,`workflowId` required; `branch`/`tag` (one required); `environment`,`labels` optional | builds.html table |
| `POST /builds/:id/cancel`, `208` when already finished | builds.html |
| Artifact URL form `/artifacts/<build-id>/<artifact-id>/<filename>` | real example in artifacts.html |
| `POST /artifacts/:secureFilename/public-url` body `{expiresAt}` → `{url, expiresAt}` | artifacts.html |
| No documented raw-log endpoint, but each build step exposes a `logUrl` (`…/builds/:id/step/:stepId`, `text/plain` with inline `<span>` colour markup) | no `…/logs` path in any v1 page; `logUrl` seen in the live `GET /builds/:id` response |
| Caches: `GET`/`DELETE /apps/:id/caches`, `DELETE …/:cacheId` | caches.html |
| No official CLI queries builds/artifacts (codemagic-cli-tools = build/deploy only) | cli-tools README |
| v1 "transitioning to our new API" banner | codemagic-rest-api.html |
| v3: OpenAPI 3.1.0, 64 paths, 212 schemas, base `/api/v3`, `x-auth-token`; no trigger/cancel/artifacts route; artifacts via `short_lived_download_url`; builds at `/teams/{team_id}/builds` with `app_id,status,workflow_id,branch,tag,label` filters + cursor paging | openapi-v3.json |
| **`GET /apps` works (200)** → `{applications[], builds[]}`; app has `_id`,`appName`,`workflowIds`,`branches` | live call |
| **`GET /apps/:id` works (200)** → `{application}` incl. `branches[]` | live call |
| **`GET /builds?appId=<id>` works (200)** → `{applications[], builds[], nextPageUrl}` (cursor paging, 30/page) | live call |
| **`GET /builds/:id` works (200)** → `{application, build}` | live call |
| Build id field is `_id` (24-char ObjectId), not `id`; `status` ∈ {finished, failed, canceled, timeout, …} | live call |
| **`GET /builds/:id` returns a `buildActions[]` array** (ordered steps; a 16-step build seen live). Each step: `name`,`type`,`status`,`startedAt`,`finishedAt`,`logUrl`,`subactions[]`. System steps carry `logUrl` directly; script steps carry it on their single subaction (which also has a `command`). Modeled as `BuildAction` in `openapi-v1.patch.json` | live call |

### ⚠️ Corrected

- **The build's artifact array is spelled `artefacts` (British), not `artifacts`.** This is the big
  one — the brief and earlier drafts used `artifacts`. Each entry has `name`, `type`, `url` (full
  authenticated download URL), `path` (the `<build-id>/<artifact-id>/<file>` secureFilename), and
  **`size`** in bytes (not `size_in_bytes`, which is a v3 thing), plus optional
  `version*`/`supportedPlatforms`/`minOsVersion`. Fixed in `openapi-v1.patch.json`.
- **`GET /builds` / `GET /builds/:id` and the `?appId=` filter are real** — undocumented in the v1
  HTML but confirmed live (200). `GET /builds` is cursor-paginated via `nextPageUrl`. `appId` works
  as a query filter even though the docs only mention it as the `POST /builds` body param.
- **`workflowId` is `null` when a build uses `codemagic.yaml`** — the yaml workflow id lives in
  `fileWorkflowId` instead.
- **`instanceType` is a real field on the build object, and `POST /builds` accepts it as input** —
  absent from the v1 docs' parameter table, but confirmed live 2026-08-26: a build started with
  `instanceType: mac_mini_m1` on a workflow that defaults to `mac_mini_m2` came back reporting
  `mac_mini_m1`, and was canceled before it started (no billable minutes). Added to
  `openapi-v1.patch.json` and exposed as `build start --instance-type`.
- **Builds & Applications APIs are "preview".** The v1 docs state they are "available for
  developers to preview … may change without advance notice." Treat as unstable; pin with tests.
- **`public-url` `expiresAt` type asymmetry** — integer (UNIX seconds) in the request, ISO-8601
  string in the response.
- **v1 docs are partly stale** — the artifacts page was last updated 2023-03-14 (others May/June 2026).

### Verified live 2026-07-15

- **`POST /builds` and `POST /builds/:id/cancel`** — confirmed live via a start→cancel→show
  round-trip on a real app. Start returns a body the client reads as `{ "buildId": "…" }`; cancel
  returns 200 on a running build (→ `.cancelled`) and the build then reports `status: canceled`.
  The 208 (already-finished) cancel path remains covered by a synthetic Replay stub only.
  The Replay `start`/`cancel` stubs match this live behaviour, so no HAR fixtures are needed.

### Verified live 2026-08-26

- **`POST /builds` accepts `instanceType`** — start→show→cancel round-trip; the requested machine
  overrode the workflow's own (see the corrected entry above).
- **`GET /builds` has no page-size parameter** — `limit`, `perPage`, `per_page`, `pageSize`, `count`
  and `take` were each sent live and ignored (30 builds returned every time). Its `nextPageUrl`
  cursor is `?appId=<id>&skip=<n>`, and `skip` honours arbitrary offsets, not just multiples of 30 —
  so `cmagic builds --next-page <n>` skips server-side.

### Still not verified

- Nothing outstanding on the endpoints the CLI uses.

### Design caveats (not corrections)

- **Response fidelity.** The v1 docs don't specify response schemas; the `Build`/`Artefact` schemas
  are now populated from live responses but keep `additionalProperties: true` for forward-compat.
- **Artifact path parameter.** `secureFilename` is itself a multi-segment path
  (`<build-id>/<artifact-id>/<file>`). OpenAPI path params can't span `/` and the generator
  percent-encodes them, so the `/artifacts/...` operations are **not** generator-safe. Download by
  fetching the artefact URL (from `build.artefacts[].url`) directly with `URLSession`.

## 6. Regenerating everything

```bash
# v3 (published)
curl -sSL -o documentation/openapi-v3.json https://codemagic.io/api/v3/schema/openapi.json

# v1 (scraped)
DIR=documentation/v1-api-docs
for slug in codemagic-rest-api applications builds artifacts caches; do
  curl -sSL -o "$DIR/$slug.html" "https://docs.codemagic.io/rest-api/$slug/"
done
swift Scripts/GenerateOpenAPIV1.swift
```

## 7. Next steps

Task-level progress (achieved + pending) is tracked in
[`roadmap/ROADMAP.md`](./roadmap/ROADMAP.md). The spec is now validated against live responses and
the swift-openapi-generator client (plus the `URLSession`-direct download / public-url / step-log
helpers) is wired and shipping the full command surface, with GitHub Actions CI running build +
test. Remaining work — `mise` distribution and a README install section — is tracked in the
roadmap.

[swift-openapi-generator]: https://github.com/apple/swift-openapi-generator
