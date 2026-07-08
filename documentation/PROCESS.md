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
swift Scripts/GenerateOpenAPIV1.swift            # defaults to the paths below
# or explicitly:
swift Scripts/GenerateOpenAPIV1.swift documentation/v1-api-docs documentation/openapi-v1.generated.json
```

The script (Foundation-only, no dependencies) extracts, per operation:

- **method + path** (`:id` → `{id}`),
- **summary** (the `<h2>` heading),
- **parameters** (the Parameters table): path params from the URL, the rest become query params
  (GET/DELETE) or `requestBody` JSON properties (POST/PUT/PATCH), with type + required flag.

It sets sensible response codes it cannot infer from prose: `200` generic for reads/writes,
`202` for DELETE (async), and an extra `208` on `/builds/:id/cancel`.

Output: **`documentation/openapi-v1.generated.json`** — 11 operations across
Applications / Builds / Artifacts / Caches.

### Two v1 spec files, on purpose

| File | Source | Use |
|---|---|---|
| `openapi-v1.generated.json` | scraped from docs by the script | reproducible, faithful to what Codemagic documents |
| `openapi-v1.yaml` | hand-curated superset | what we actually feed to the generator |

The **curated** `openapi-v1.yaml` enriches the generated baseline with things the docs omit:
tighter response schemas (`Application`/`Build`/`Artifact`/`Cache`) and the **undocumented but
real** `GET /builds` and `GET /builds/:id` (needed to list/inspect builds — the v1 docs describe
neither). Regenerating the `.json` is how we detect when the docs drift; the `.yaml` is where we
apply judgement.

## 5. Known caveats

- **Response fidelity.** The v1 docs don't specify response schemas, so generated responses are
  open objects (`additionalProperties: true`). Tighten against live `curl` samples with a real
  `CM_TOKEN`.
- **Undocumented reads.** `GET /builds` and `GET /builds/:id` are not in the v1 docs, so the
  scraper cannot emit them. They live only in the curated `openapi-v1.yaml`.
- **Artifact path parameter.** `secureFilename` is itself a multi-segment path
  (`<build-id>/<artifact-id>/<file>`). OpenAPI path params can't span `/` and the generator
  percent-encodes them, so the `/artifacts/...` operations are **not** generator-safe. Download by
  fetching the artifact URL (from `build.artifacts[].url`) directly with `URLSession`.
- **Query params for `GET /builds`.** Not documented; confirm empirically (branch? limit?).

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

1. Validate `openapi-v1.yaml` against live responses; tighten schemas.
2. Wire swift-openapi-generator (runtime + urlsession transport) against `openapi-v1.yaml`.
3. Add the thin `URLSession` artifact-download helper (bypassing the generator).

[swift-openapi-generator]: https://github.com/apple/swift-openapi-generator
