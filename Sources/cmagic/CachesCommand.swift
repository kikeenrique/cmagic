import ArgumentParser
import CodemagicApiKit

struct Caches: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "caches",
        abstract: "List and delete build caches.",
        subcommands: [List.self, Delete.self],
        defaultSubcommand: List.self
    )

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "list", abstract: "List caches for an app.")

        @Option(name: [.short, .long], help: "Application id (defaults to `app` in config).")
        var app: String?

        @OptionGroup var out: OutputOptions

        func run() async throws {
            let (config, cm) = try Session.loadConfigAndClient()
            let appId = try Session.resolveAppId(app, config: config)
            let caches = try await cm.caches(appId: appId)
            if out.json { try out.emit(caches); return }
            print("WORKFLOW\tPLATFORM\tSIZE\tID")
            for c in caches {
                print("\(c.workflowId ?? "-")\t\(c.platform ?? "-")\t\(c.size.map(bytesHuman) ?? "-")\t\(c._id)")
            }
        }
    }

    struct Delete: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "delete", abstract: "Delete all caches, or one by id.")

        @Option(name: [.short, .long], help: "Application id (defaults to `app` in config).")
        var app: String?

        @Option(name: .long, help: "Delete only this cache id (otherwise all caches).")
        var cacheId: String?

        @OptionGroup var out: OutputOptions

        func run() async throws {
            let (config, cm) = try Session.loadConfigAndClient()
            let appId = try Session.resolveAppId(app, config: config)
            if let cacheId {
                try await cm.deleteCache(appId: appId, cacheId: cacheId)
                if out.json { try out.emit(["appId": appId, "cacheId": cacheId, "status": "accepted"]); return }
                print("requested deletion of cache \(cacheId) (processed asynchronously)")
            } else {
                try await cm.deleteAllCaches(appId: appId)
                if out.json { try out.emit(["appId": appId, "scope": "all", "status": "accepted"]); return }
                print("requested deletion of all caches for \(appId) (processed asynchronously)")
            }
        }
    }
}
