# Codemagic Swift CLI

```
 ██████╗███╗   ███╗ █████╗  ██████╗ ██╗ ██████╗
██╔════╝████╗ ████║██╔══██╗██╔════╝ ██║██╔════╝
██║     ██╔████╔██║███████║██║  ███╗██║██║     
██║     ██║╚██╔╝██║██╔══██║██║   ██║██║██║     
╚██████╗██║ ╚═╝ ██║██║  ██║╚██████╔╝██║╚██████╗
 ╚═════╝╚═╝     ╚═╝╚═╝  ╚═╝ ╚═════╝ ╚═╝ ╚═════╝
        Codemagic from your terminal · unofficial CLI
```

[![Release](https://img.shields.io/github/v/release/kikeenrique/cmagic?sort=semver)](https://github.com/kikeenrique/cmagic/releases)
[![CI](https://img.shields.io/github/actions/workflow/status/kikeenrique/cmagic/ci.yml?branch=main&label=CI)](https://github.com/kikeenrique/cmagic/actions/workflows/ci.yml)
![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-lightgrey)
![Swift](https://img.shields.io/badge/swift-6.0-orange)

**cmagic** is a command-line tool for [Codemagic](https://codemagic.io), the CI/CD service for
mobile apps. It lets you check on your builds and grab their output — logs, test results, built
apps — from the terminal, without opening the Codemagic web dashboard or hand-writing API calls.
This is an **unofficial** client, not affiliated with or supported by Codemagic; it simply talks to
their public REST API.

## Overview

The package is a Swift **library (`CodemagicApiKit`)** plus a thin **executable (`cmagic`)** built on
top of the [Codemagic](https://codemagic.io) REST API — inspect builds and pull their artifacts
(e.g. a red build's `TestResults-*.xcresult`) straight from the terminal. Codemagic ships no
official CLI for querying the service, so the only other remote-access route is raw `curl`; this
package replaces that with a typed Swift client.

## Install

Prebuilt universal (arm64 + x86_64) macOS binaries are attached to each
[GitHub release](https://github.com/kikeenrique/cmagic/releases).

```bash
# Homebrew
brew install kikeenrique/tap/cmagic

# mise (github backend; ubi: also works but is deprecated upstream)
mise use -g github:kikeenrique/cmagic        # latest, or pin @v0.2.0
```

Or build from source (see below) and copy `.build/release/cmagic` onto your `PATH`.

## Build, test, run

```bash
swift build            # or: mise run build
swift test             # or: mise run test
```

## Usage

The token is read from the config file (see [Authentication](#authentication)).

```bash
cmagic --version                              # the release this binary was built from
cmagic apps                                   # list apps: <id>  <name>
cmagic builds --app <id> --limit 10           # recent builds (add --branch <b> to filter)
cmagic builds --app <id> --next-page 60 --limit 20  # builds 61-80 (the API's own skip)
cmagic build show <buildId>                    # one build's detail + artefacts
cmagic build show <buildId> --steps            # + each step's status and duration
cmagic build logs <buildId> [--step N] [--raw]  # step logs (plain text; --raw keeps colour markup)
cmagic build start --app <id> --workflow <w> --branch main [--instance-type mac_mini_m2]
cmagic build cancel <buildId>

# the flagship: pull the latest build's artefact for a branch, auto-unzipping zip/xcresult
cmagic artifacts pull --app <id> --branch main --name TestResults -o ./out
cmagic artifacts public-url --app <id> --branch main --name TestResults --expires-in-hours 24
# ...or target a specific build by id (--branch/--app not needed)
cmagic artifacts pull --build-id <buildId> --name TestResults -o ./out
cmagic artifacts public-url --build-id <buildId> --name TestResults

cmagic caches list --app <id>
cmagic caches delete --app <id> [--cache-id <id>]
```

`--app` and `--branch` fall back to `app`/`branch` in the config file if set. Every command accepts
`--json` for machine-readable output (pipe into `jq`). Run any command with `--help` for options.

```bash
cmagic builds --app <id> --json | jq '.builds[] | select(.status=="failed")._id'
```

### Paging builds

`GET /builds` serves 30 builds per call — there is no page-size parameter — and its `nextPageUrl`
cursor is a `skip=<n>` offset. `cmagic builds` follows that cursor as needed to satisfy `--limit`,
and `--next-page <n>` starts the listing `n` builds in, sent as the API's own `skip`. When builds are
left over, the offset that resumes right after the last row shown is printed as a `next-page:` line
(`nextPage` under `--json`, `null` at the end of the history), so chained calls neither skip nor
repeat a build:

```bash
cmagic builds --app <id> --limit 25              # … then: next-page: 25
cmagic builds --app <id> --next-page 25 --limit 25
cmagic builds --app <id> --limit 0 --json        # no cap: the whole history
```

`--max-pages` (default 20) caps how many 30-build pages a single call may fetch — it only bites with
`--branch`, which is filtered client-side since the API filters by app only. Note that paging is
positional rather than anchored to a build: a build started between two calls shifts the history
down, so a resumed listing can repeat one. The API offers no stable cursor, so de-duplicate by
`_id` if that matters.

## Approach

The client is generated with Apple's [swift-openapi-generator] rather than hand-written. We target
the **v1** API (`https://api.codemagic.io`) because it has the operations we need — trigger, cancel,
artifacts, caches — which the newer v3 API does not yet expose. Codemagic publishes no
machine-readable spec for v1, so we build one from its HTML docs (see below). The official **v3**
spec is kept for reference.

## Repository layout

```
Package.swift
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
Tests/CodemagicApiKitTests/      # 28 offline tests (config, decoding, auth, Replay stubs)
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

[swift-openapi-generator]: https://github.com/apple/swift-openapi-generator
