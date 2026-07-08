# Codemagic Swift CLI

A Swift **library (`CodemagicApiKit`)** + thin **executable (`cmagic`)** for the
[Codemagic](https://codemagic.io) REST API — inspect builds and pull their artifacts (e.g. a red
build's `TestResults-*.xcresult`) straight from the terminal. Codemagic ships no official CLI for
querying the service, so today the only remote-access route is raw `curl`; this package replaces
that with a typed Swift client.

> **Status: early.** API research and the OpenAPI specs are done; the Swift package is not yet
> scaffolded. See [`documentation/roadmap/ROADMAP.md`](documentation/roadmap/ROADMAP.md) for what's
> done and what's next.

## Approach

The client is generated with Apple's [swift-openapi-generator] rather than hand-written. We target
the **v1** API (`https://api.codemagic.io`) because it has the operations we need — trigger, cancel,
artifacts, caches — which the newer v3 API does not yet expose. Codemagic publishes no
machine-readable spec for v1, so we build one from its HTML docs (see below). The official **v3**
spec is kept for reference.

## Repository layout

```
Scripts/
  GenerateOpenAPIV1.swift        # scrapes the v1 HTML docs → OpenAPI, merging a hand-authored patch
documentation/
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
(enrichment) and re-run the script — never hand-edit the generated file. Full details in
[`documentation/PROCESS.md`](documentation/PROCESS.md).

## Authentication

Every request uses the header `x-auth-token: <token>` (generate it in the Codemagic UI under
Account settings / Integrations → API token). The token is read from a **config file only**:

- **Path:** `$XDG_CONFIG_HOME/cmagic/config.toml`, falling back to
  `~/.config/cmagic/config.toml`
- **Format (TOML):** `token = "cm_xxxxxxxx"`
- Keep it `chmod 600`; the CLI warns if it is group/world-readable, fails clearly when absent, and
  never logs the token.

There is intentionally no `--token` flag or `CM_TOKEN` env var (see
[`documentation/roadmap/ROADMAP.md`](documentation/roadmap/ROADMAP.md#authentication-decided)).

[swift-openapi-generator]: https://github.com/apple/swift-openapi-generator
