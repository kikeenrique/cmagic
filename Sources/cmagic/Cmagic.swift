import ArgumentParser
import CodemagicApiKit

@main
struct Cmagic: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cmagic",
        abstract: "Inspect Codemagic builds and pull their artefacts from the terminal.",
        subcommands: [Apps.self, Builds.self, Build.self, Artifacts.self]
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

    func run() async throws {
        let (_, cm) = try Session.loadConfigAndClient()
        for app in try await cm.apps() {
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

    func run() async throws {
        let (config, cm) = try Session.loadConfigAndClient()
        let appId = try Session.resolveAppId(app, config: config)
        var builds = try await cm.builds(appId: appId)
        let branchFilter = branch ?? config.branch
        if let branchFilter { builds = builds.filter { $0.branch == branchFilter } }
        builds = Array(builds.prefix(max(0, limit)))

        print("STATUS\tBRANCH\tARTEFACTS\tID")
        for b in builds {
            let count = b.artefacts?.count ?? 0
            print("\(b.status ?? "?")\t\(b.branch ?? b.tag ?? "-")\t\(count)\t\(b._id)")
        }
    }
}

// MARK: - build <id>

struct Build: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "build", abstract: "Show one build's detail.")

    @Argument(help: "Build id.")
    var buildId: String

    func run() async throws {
        let (_, cm) = try Session.loadConfigAndClient()
        let b = try await cm.build(id: buildId)
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
    }
}

func bytesHuman(_ bytes: Int) -> String {
    let units = ["B", "KB", "MB", "GB"]
    var value = Double(bytes)
    var unit = 0
    while value >= 1024 && unit < units.count - 1 { value /= 1024; unit += 1 }
    return unit == 0 ? "\(bytes) B" : String(format: "%.1f %@", value, units[unit])
}
