import ArgumentParser
import CodemagicApiKit

@main
struct Cmagic: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cmagic",
        abstract: "Inspect Codemagic builds and pull their artefacts from the terminal.",
        subcommands: [Apps.self]
    )
}

/// `cmagic apps` — list applications for the authenticated token.
struct Apps: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "apps",
        abstract: "List applications (id and name)."
    )

    func run() async throws {
        let cm = try Codemagic.fromConfig()
        let payload = try await cm.underlying.getApps().ok.body.json
        let apps = payload.applications ?? []
        for app in apps {
            print("\(app._id)\t\(app.appName ?? "")")
        }
    }
}
