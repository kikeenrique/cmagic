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
(`openapi-v3.json`), and the codemagic-cli-tools repo. Legend: ✅ confirmed · ⚠️ corrected /
assumption · 🔑 needs a live `CM_TOKEN`.

### ✅ Confirmed

| Claim | Evidence |
|---|---|
| v1 base URL `https://api.codemagic.io`; auth header `x-auth-token` | curl examples throughout v1 docs (12× `x-auth-token`) |
| v1 token location "Account settings > API token" | applications overview |
| `POST /builds` params: `appId`,`workflowId` required; `branch`/`tag` (one required); `environment`,`labels` optional | builds.html table |
| `POST /builds/:id/cancel`, `208` when already finished | builds.html |
| Artifact URL form `/artifacts/<build-id>/<artifact-id>/<filename>` | real example in artifacts.html |
| `POST /artifacts/:secureFilename/public-url` body `{expiresAt}` → `{url, expiresAt}` | artifacts.html |
| No documented raw-log endpoint | no `…/logs` path in any v1 page |
| Caches: `GET`/`DELETE /apps/:id/caches`, `DELETE …/:cacheId` | caches.html |
| No official CLI queries builds/artifacts (codemagic-cli-tools = build/deploy only) | cli-tools README |
| v1 "transitioning to our new API" banner | codemagic-rest-api.html |
| v3: OpenAPI 3.1.0, 64 paths, 212 schemas, base `/api/v3`, `x-auth-token`; no trigger/cancel/artifacts route; artifacts via `short_lived_download_url`; builds at `/teams/{team_id}/builds` with `app_id,status,workflow_id,branch,tag,label` filters + cursor paging | openapi-v3.json |

### ⚠️ Corrected / assumptions

- **Builds & Applications APIs are "preview".** The v1 docs state they are "available for
  developers to preview … may change without advance notice." Treat the build/app surface as
  unstable and pin behaviour with tests. (Neither the brief nor earlier drafts noted this.)
- **`GET /builds` and `GET /builds/:id` are not in the v1 docs at all** — no such section exists.
  They come from `openapi-v1.patch.json`, sourced from the handoff brief (§3), and are **not**
  re-verified. The `?appId=` filter is a guess — `appId` is documented only as the `POST /builds`
  body param, never as a query filter.
- **`instanceType` is not documented.** The brief lists it as an optional `POST /builds` param but
  it is absent from the documented table; kept out of the spec pending a live check.
- **`public-url` `expiresAt` type asymmetry** — integer (UNIX seconds) in the request, ISO-8601
  string in the response.
- **v1 docs are partly stale** — the artifacts page was last updated 2023-03-14 (others May/June 2026).

### 🔑 Needs a live token

Response-shape and behavioural claims that only an API call can confirm: `GET /apps` shape
(`applications[]` with `_id`/`appName`/`workflowIds`/`workflows`), `GET /apps/:id` `branches[]`,
whether the two build GETs exist and their shape, whether `?appId=` filters, v1 build field names
(`_id` vs `id`, `artifacts[].{url,name,type}`, `status` values), whether `POST /builds` accepts
`instanceType`, and that auth/base URL behave as documented. Until these pass, the `Build`/
`Artifact` schemas stay loose (`additionalProperties: true`).

### Design caveats (not corrections)

- **Response fidelity.** The v1 docs don't specify response schemas, so scraped responses are open
  objects (`additionalProperties: true`); tighten via the patch or live `curl` samples.
- **Artifact path parameter.** `secureFilename` is itself a multi-segment path
  (`<build-id>/<artifact-id>/<file>`). OpenAPI path params can't span `/` and the generator
  percent-encodes them, so the `/artifacts/...` operations are **not** generator-safe. Download by
  fetching the artifact URL (from `build.artifacts[].url`) directly with `URLSession`.

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
[`roadmap/ROADMAP.md`](./roadmap/ROADMAP.md). The immediate next steps: validate the spec against
live responses and tighten schemas via the patch, then wire swift-openapi-generator
(runtime + urlsession transport) against `openapi-v1.generated.json` and add the thin `URLSession`
artifact-download helper (bypassing the generator).

[swift-openapi-generator]: https://github.com/apple/swift-openapi-generator
