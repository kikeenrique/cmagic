import ArgumentParser
import CodemagicApiKit
import Foundation

struct Artifacts: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "artifacts",
        abstract: "Work with build artefacts.",
        subcommands: [Pull.self, PublicURL.self]
    )

    /// `cmagic artifacts pull` — resolve the latest build for a branch, match an
    /// artefact by name, download it, and auto-unzip `.zip`/`.xcresult` archives.
    struct Pull: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "pull", abstract: "Download an artefact from the latest matching build.")

        @Option(name: [.short, .long], help: "Application id (defaults to `app` in config).")
        var app: String?

        @Option(name: [.short, .long], help: "Branch to pull the latest build from (defaults to `branch` in config).")
        var branch: String?

        @Option(name: [.short, .long], help: "Artefact name (substring, case-insensitive).")
        var name: String

        @Option(name: [.short, .long], help: "Output directory.")
        var output: String = "."

        @Flag(help: "Keep the downloaded archive after unzipping.")
        var keepArchive = false

        func run() async throws {
            let (config, cm) = try Session.loadConfigAndClient()
            let appId = try Session.resolveAppId(app, config: config)
            let branchFilter = branch ?? config.branch

            guard let build = try await cm.latestBuild(appId: appId, branch: branchFilter) else {
                throw CleanExit.message("No build found for app \(appId)\(branchFilter.map { " on branch \($0)" } ?? "").")
            }
            let artefacts = build.artefacts ?? []
            guard let artefact = artefacts.first(where: { ($0.name ?? "").localizedCaseInsensitiveContains(name) }) else {
                let names = artefacts.compactMap(\.name).joined(separator: ", ")
                throw CleanExit.message("No artefact matching \"\(name)\" in build \(build._id). Available: \(names.isEmpty ? "(none)" : names)")
            }
            guard let url = URL(string: artefact.url) else {
                throw CleanExit.message("Artefact \(artefact.name ?? "?") has an invalid URL.")
            }

            let outDir = URL(fileURLWithPath: output, isDirectory: true)
            try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

            FileHandle.standardError.write(Data("Downloading \(artefact.name ?? url.lastPathComponent) from build \(build._id)…\n".utf8))
            let downloader = ArtefactDownloader(token: config.token)
            let file = try await downloader.download(from: url, to: outDir)

            if Archive.isZip(file) {
                try Archive.unzip(file, into: outDir)
                if !keepArchive { try? FileManager.default.removeItem(at: file) }
                print(outDir.path)
            } else {
                print(file.path)
            }
        }
    }

    /// `cmagic artifacts public-url` — mint a tokenless, expiring download URL for
    /// an artefact matched on the latest build (same resolution as `pull`).
    struct PublicURL: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "public-url", abstract: "Create a public (tokenless) download URL for an artefact.")

        @Option(name: [.short, .long], help: "Application id (defaults to `app` in config).")
        var app: String?

        @Option(name: [.short, .long], help: "Branch (defaults to `branch` in config).")
        var branch: String?

        @Option(name: [.short, .long], help: "Artefact name (substring, case-insensitive).")
        var name: String

        @Option(name: .long, help: "Hours until the URL expires.")
        var expiresInHours: Double = 24

        func run() async throws {
            let (config, cm) = try Session.loadConfigAndClient()
            let appId = try Session.resolveAppId(app, config: config)
            let branchFilter = branch ?? config.branch

            guard let build = try await cm.latestBuild(appId: appId, branch: branchFilter) else {
                throw CleanExit.message("No build found for app \(appId)\(branchFilter.map { " on branch \($0)" } ?? "").")
            }
            let artefacts = build.artefacts ?? []
            guard let artefact = artefacts.first(where: { ($0.name ?? "").localizedCaseInsensitiveContains(name) }),
                  let path = artefact.path else {
                let names = artefacts.compactMap(\.name).joined(separator: ", ")
                throw CleanExit.message("No artefact matching \"\(name)\" in build \(build._id). Available: \(names.isEmpty ? "(none)" : names)")
            }
            let result = try await cm.artefactPublicURL(
                artefactPath: path,
                expiresAt: Date().addingTimeInterval(expiresInHours * 3600)
            )
            print(result.url)
            if let expiresAt = result.expiresAt {
                FileHandle.standardError.write(Data("expires: \(expiresAt)\n".utf8))
            }
        }
    }
}

/// Tiny zip helper backed by `/usr/bin/unzip`.
enum Archive {
    static func isZip(_ file: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return false }
        defer { try? handle.close() }
        let magic = try? handle.read(upToCount: 4)
        return magic == Data([0x50, 0x4B, 0x03, 0x04]) // "PK\x03\x04"
    }

    static func unzip(_ file: URL, into directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", "-o", file.path, "-d", directory.path]
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw CleanExit.message("unzip failed (exit \(process.terminationStatus)) for \(file.lastPathComponent)")
        }
    }
}
