import ArgumentParser
import CodemagicApiKit
import Foundation

@main
struct Cmagic: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cmagic",
        abstract: "Inspect Codemagic builds and pull their artefacts from the terminal.",
        subcommands: [Apps.self, Builds.self, Build.self, Artifacts.self, Caches.self]
    )
}

/// Shared loading of the config + client, plus app-id resolution.
enum Session {
    static func loadConfigAndClient() throws -> (CmagicConfig, Codemagic) {
        let config = try CmagicConfig.load()
        return (config, Codemagic(token: config.token))
    }

    /// `--app` wins, else the config `app`, else a validation error.
    static func resolveAppId(_ flag: String?, config: CmagicConfig) throws -> String {
        if let flag, !flag.isEmpty { return flag }
        if let app = config.app { return app }
        throw ValidationError("No application id. Pass --app <id> or set `app = \"…\"` in the config file.")
    }
}

// MARK: - apps

struct Apps: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "apps", abstract: "List applications (id and name).")

    @OptionGroup var out: OutputOptions

    func run() async throws {
        let (_, cm) = try Session.loadConfigAndClient()
        let apps = try await cm.apps()
        if out.json { try out.emit(apps); return }
        for app in apps {
            print("\(app._id)\t\(app.appName ?? "")")
        }
    }
}

// MARK: - builds

struct Builds: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "builds", abstract: "List recent builds for an app.")

    @Option(name: [.short, .long], help: "Application id (defaults to `app` in config).")
    var app: String?

    @Option(name: [.short, .long], help: "Filter to this branch.")
    var branch: String?

    @Option(name: [.short, .long], help: "Max builds to show.")
    var limit: Int = 20

    @OptionGroup var out: OutputOptions

    func run() async throws {
        let (config, cm) = try Session.loadConfigAndClient()
        let appId = try Session.resolveAppId(app, config: config)
        var builds = try await cm.builds(appId: appId)
        let branchFilter = branch ?? config.branch
        if let branchFilter { builds = builds.filter { $0.branch == branchFilter } }
        builds = Array(builds.prefix(max(0, limit)))

        if out.json { try out.emit(builds); return }
        print("STATUS\tBRANCH\tARTEFACTS\tID")
        for b in builds {
            let count = b.artefacts?.count ?? 0
            print("\(b.status ?? "?")\t\(b.branch ?? b.tag ?? "-")\t\(count)\t\(b._id)")
        }
    }
}

// MARK: - build show|start|cancel

struct Build: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "build",
        abstract: "Inspect and control a build.",
        subcommands: [Show.self, Start.self, Cancel.self, Logs.self]
    )

    struct Show: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "show", abstract: "Show one build's detail.")

        @Argument(help: "Build id.")
        var buildId: String

        @Flag(name: .long, help: "Show the build's steps (name, status, duration).")
        var steps: Bool = false

        @OptionGroup var out: OutputOptions

        func run() async throws {
            let (_, cm) = try Session.loadConfigAndClient()
            let b = try await cm.build(id: buildId)
            if out.json { try out.emit(b); return }
            print("id:         \(b._id)")
            print("status:     \(b.status ?? "?")")
            print("branch/tag: \(b.branch ?? b.tag ?? "-")")
            print("workflow:   \(b.workflowId ?? b.fileWorkflowId ?? "-")")
            print("created:    \(b.createdAt ?? "-")")
            print("started:    \(b.startedAt ?? "-")")
            print("finished:   \(b.finishedAt ?? "-")")
            let arts = b.artefacts ?? []
            print("artefacts:  \(arts.count)")
            for a in arts {
                print("  - \(a.name ?? "?")\t\(a.size.map(bytesHuman) ?? "-")")
            }
            let acts = b.buildActions ?? []
            print("steps:      \(acts.count)")
            if steps {
                for a in acts {
                    let dur = duration(from: a.startedAt, to: a.finishedAt)
                    print("  \(statusMark(a.status)) \(durationHuman(dur))\t\(a.name ?? a.command?.firstLine ?? "?")")
                }
            }
        }
    }

    struct Start: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "start", abstract: "Trigger a new build.")

        @Option(name: [.short, .long], help: "Application id (defaults to `app` in config).")
        var app: String?

        @Option(name: [.short, .long], help: "Workflow id (from the Workflow Editor / codemagic.yaml).")
        var workflow: String

        @Option(name: [.short, .long], help: "Branch to build (one of --branch/--tag required).")
        var branch: String?

        @Option(name: [.short, .long], help: "Tag to build (one of --branch/--tag required).")
        var tag: String?

        @OptionGroup var out: OutputOptions

        func validate() throws {
            if (branch ?? "").isEmpty && (tag ?? "").isEmpty {
                throw ValidationError("Provide --branch or --tag.")
            }
        }

        func run() async throws {
            let (config, cm) = try Session.loadConfigAndClient()
            let appId = try Session.resolveAppId(app, config: config)
            let buildId = try await cm.startBuild(appId: appId, workflowId: workflow, branch: branch, tag: tag)
            if out.json { try out.emit(["buildId": buildId]); return }
            print(buildId)
        }
    }

    struct Cancel: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "cancel", abstract: "Cancel a running build.")

        @Argument(help: "Build id.")
        var buildId: String

        @OptionGroup var out: OutputOptions

        func run() async throws {
            let (_, cm) = try Session.loadConfigAndClient()
            let outcome = try await cm.cancelBuild(id: buildId)
            if out.json {
                try out.emit(["buildId": buildId, "outcome": outcome == .cancelled ? "cancelled" : "alreadyFinished"])
                return
            }
            switch outcome {
            case .cancelled: print("cancelled \(buildId)")
            case .alreadyFinished: print("build \(buildId) had already finished")
            }
        }
    }

    struct Logs: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "logs", abstract: "Print a build's step logs.")

        @Argument(help: "Build id.")
        var buildId: String

        @Option(name: [.short, .long], help: "Only this step (1-based, in the order `show --steps` lists).")
        var step: Int?

        @Flag(name: .long, help: "Keep the raw <span> markup instead of stripping it to plain text.")
        var raw: Bool = false

        func validate() throws {
            if let step, step < 1 { throw ValidationError("--step is 1-based; pass a value >= 1.") }
        }

        func run() async throws {
            let (_, cm) = try Session.loadConfigAndClient()
            let actions = try await cm.build(id: buildId).buildActions ?? []
            guard !actions.isEmpty else { throw ValidationError("build \(buildId) has no steps.") }

            let selected: [(offset: Int, action: Codemagic.BuildAction)]
            if let step {
                guard step <= actions.count else {
                    throw ValidationError("--step \(step) is out of range (build has \(actions.count) steps).")
                }
                selected = [(step - 1, actions[step - 1])]
            } else {
                selected = actions.enumerated().map { ($0.offset, $0.element) }
            }

            for (offset, action) in selected {
                let header = "===== [\(offset + 1)/\(actions.count)] \(action.name ?? "step") (\(action.status ?? "?")) ====="
                print(header)
                let urls = stepLogURLs(action)
                if urls.isEmpty { print("(no log for this step)"); continue }
                for url in urls {
                    let body = try await cm.stepLog(logUrl: url)
                    print(raw ? body : stripSpanMarkup(body), terminator: body.hasSuffix("\n") ? "" : "\n")
                }
            }
        }
    }
}

/// A step's log URLs: its own `logUrl`, else its subactions' (script steps put the
/// log on the single subaction). Recurses so nested subactions are covered.
func stepLogURLs(_ action: Codemagic.BuildAction) -> [String] {
    if let url = action.logUrl { return [url] }
    return (action.subactions ?? []).flatMap(stepLogURLs)
}

/// Strip the inline `<span style="…">…</span>` colour markup the log endpoint
/// emits, and unescape the few HTML entities it uses, leaving plain text.
func stripSpanMarkup(_ s: String) -> String {
    var out = ""
    out.reserveCapacity(s.count)
    var inTag = false
    for ch in s {
        if ch == "<" { inTag = true; continue }
        if ch == ">" { inTag = false; continue }
        if !inTag { out.append(ch) }
    }
    return out
        .replacingOccurrences(of: "&lt;", with: "<")
        .replacingOccurrences(of: "&gt;", with: ">")
        .replacingOccurrences(of: "&quot;", with: "\"")
        .replacingOccurrences(of: "&#39;", with: "'")
        .replacingOccurrences(of: "&amp;", with: "&")
}

func bytesHuman(_ bytes: Int) -> String {
    let units = ["B", "KB", "MB", "GB"]
    var value = Double(bytes)
    var unit = 0
    while value >= 1024 && unit < units.count - 1 { value /= 1024; unit += 1 }
    return unit == 0 ? "\(bytes) B" : String(format: "%.1f %@", value, units[unit])
}

/// A short glyph for a build-step status, so a run reads at a glance.
func statusMark(_ status: String?) -> String {
    switch status {
    case "success": return "✓"
    case "failed", "error": return "✗"
    case "skipped": return "–"
    case "building", "queued", nil: return "…"
    default: return "?"
    }
}

/// Seconds between two ISO-8601 timestamps, or nil if either is missing/unparseable.
func duration(from start: String?, to end: String?) -> TimeInterval? {
    guard let start, let end,
          let s = isoDate(start), let e = isoDate(end) else { return nil }
    return e.timeIntervalSince(s)
}

private func isoDate(_ s: String) -> Date? {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
}

/// `mm:ss` (or `h:mm:ss`) from seconds; `-` when unknown.
func durationHuman(_ seconds: TimeInterval?) -> String {
    guard let seconds, seconds >= 0 else { return "    -" }
    let total = Int(seconds.rounded())
    let h = total / 3600, m = (total % 3600) / 60, s = total % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%2d:%02d", m, s)
}

extension String {
    var firstLine: String? {
        split(whereSeparator: \.isNewline).first.map(String.init)
    }
}
