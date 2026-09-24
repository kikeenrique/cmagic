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
![Platform](https://img.shields.io/badge/platform-macOS%2013%2B%20%7C%20Linux-lightgrey)
![Swift](https://img.shields.io/badge/swift-6.0-orange)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

**cmagic** is a command-line tool for [Codemagic](https://codemagic.io), the CI/CD service for
mobile apps. It lets you check on your builds and grab their output — logs, test results, built
apps — from the terminal, without opening the Codemagic web dashboard or hand-writing API calls.

It is an **unofficial** client, not affiliated with or supported by Codemagic; it simply talks to
their public REST API. The same client is also available as a Swift library, `CodemagicApiKit`, for
calling the API from your own tools.

## What you can do

- **List** your apps and their recent builds, optionally filtered by branch
- **Inspect** a build — its status, each step with its duration, and its artefacts
- **Pull artefacts** in one command — say, a failed build's `TestResults.xcresult` — unzipped and
  ready to open
- **Read step logs** as plain text
- **Start and cancel** builds, and **share** an artefact through a time-limited public link
- **Clear caches** for an app
- **Script it** — every command speaks `--json` for piping into `jq`

## Install

```bash
# Homebrew
brew install kikeenrique/tap/cmagic

# mise (github backend; ubi: also works but is deprecated upstream)
mise use -g github:kikeenrique/cmagic        # latest, or pin @v0.4.1
```

Or download a binary from the [releases page](https://github.com/kikeenrique/cmagic/releases).
Each release has a universal (arm64 + x86_64) macOS binary and, from 0.4.0 on, Linux binaries for
x86_64 and aarch64 in two variants. All of them bundle the Swift runtime, so no toolchain is
needed. Installers pick the right one automatically; downloading by hand, take `-gnu` unless you
know you are on musl.

| Asset | Platform |
|---|---|
| `cmagic-{aarch64,x86_64}-apple-darwin.tar.gz` | macOS 13+ (one universal binary under both names) |
| `cmagic-{aarch64,x86_64}-unknown-linux-gnu.tar.gz` | Linux, glibc 2.34+ |
| `cmagic-{aarch64,x86_64}-unknown-linux-musl.tar.gz` | Linux, any libc — fully static |
| `SHA256SUMS` | checksums for all of the above |

To check a download, run this in the folder you saved it to — `--ignore-missing` checks just the
files you have:

```bash
shasum -a 256 --ignore-missing -c SHA256SUMS    # macOS
sha256sum --ignore-missing -c SHA256SUMS        # Linux
```

### Linux notes

- **Which variant.** The `-gnu` build needs **glibc 2.34 or newer** — RHEL 9,
  Debian 12, Ubuntu 22.04 and anything later — and loads `libcurl`, `libstdc++`
  and `libgcc_s` from the system. Almost every distribution has those installed;
  if yours doesn't, it fails at startup with `libcurl.so.4: cannot open shared
  object file`, and the fix is to install `libcurl` (`libcurl4` on Debian and
  Ubuntu). The `-musl` build is fully static with no dependencies at all, so it
  runs anywhere, including minimal and distroless images the `-gnu` build can't.
- **TLS trust store.** Neither variant ships a CA bundle; both read the host's.
  Distributions install one with the `ca-certificates` package, but minimal and
  distroless images often do not, and every request then fails with a certificate
  error. Install `ca-certificates`, or point the binary at a bundle with
  `SSL_CERT_FILE=/path/to/ca-bundle.crt`.
- **`unzip`.** `cmagic artifacts pull` shells out to `unzip` to expand `.zip` and
  `.xcresult` artefacts. It is preinstalled on macOS but not on every Linux image;
  `cmagic` reports it clearly and keeps the archive when it is missing.

## Getting started

**1. Get an API token** from the Codemagic UI, under Account settings / Integrations → API token.

**2. Save it** in `~/.config/cmagic/config.toml` (or `$XDG_CONFIG_HOME/cmagic/config.toml`), and
keep the file private with `chmod 600` — cmagic warns if others can read it, and never logs the
token:

```toml
token = "cm_xxxxxxxx"
# app = "664..."     # optional: default for --app
# branch = "main"    # optional: default for --branch
```

**3. Try it:**

```bash
cmagic apps                                   # list apps: <id>  <name>
cmagic builds --app <id> --limit 10           # recent builds (add --branch <b> to filter)
cmagic build show <buildId> --steps           # one build: status, steps, artefacts
cmagic build logs <buildId> [--step N]        # step logs as plain text

# the flagship: pull the latest build's artefact for a branch, auto-unzipping zip/xcresult
cmagic artifacts pull --app <id> --branch main --name TestResults -o ./out
cmagic artifacts pull --build-id <buildId> --name TestResults -o ./out   # or from a specific build
cmagic artifacts public-url --app <id> --branch main --name TestResults --expires-in-hours 24

cmagic build start --app <id> --workflow <w> --branch main [--instance-type mac_mini_m2]
cmagic build cancel <buildId>

cmagic caches list --app <id>
cmagic caches delete --app <id> [--cache-id <id>]
```

Every command takes `--help` for its options, and `--json` for machine-readable output:

```bash
cmagic builds --app <id> --json | jq '.builds[] | select(.status=="failed")._id'
```

**Paging.** Codemagic serves builds 30 at a time. `cmagic builds` fetches as many pages as
`--limit` needs (`--limit 0` lists the whole history), and when builds remain it prints a
`next-page:` offset to resume from with `--next-page`. Paging is positional, so a build started
between two calls can show up twice — de-duplicate by `_id` if that matters.

## Development

Building from source, running the tests, how the code is laid out, how the API client is generated,
and how releases are cut are all in [`documentation/DEVELOPMENT.md`](documentation/DEVELOPMENT.md).

## License

cmagic is available under the [MIT License](LICENSE). "Codemagic" is a trademark of its owner; this
project is independent of it.
