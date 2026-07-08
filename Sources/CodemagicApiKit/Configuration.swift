import Foundation

/// Errors surfaced by CodemagicApiKit.
public enum CodemagicError: Error, CustomStringConvertible, Sendable {
    case configFileMissing(path: String)
    case tokenMissing(path: String)

    public var description: String {
        switch self {
        case .configFileMissing(let path):
            return "No config file at \(path). Create it with:\n\n    token = \"<your Codemagic API token>\"\n"
        case .tokenMissing(let path):
            return "No `token` found in \(path). Add a line:\n\n    token = \"<your Codemagic API token>\"\n"
        }
    }
}

/// The `cmagic` configuration, loaded from a TOML config file only.
///
/// Location: `$XDG_CONFIG_HOME/cmagic/config.toml`, falling back to
/// `~/.config/cmagic/config.toml`. Format: `token = "cm_…"`.
public struct CmagicConfig: Sendable {
    public var token: String

    public init(token: String) {
        self.token = token
    }

    /// The resolved config-file path (honours `XDG_CONFIG_HOME`).
    public static var defaultPath: String {
        let env = ProcessInfo.processInfo.environment
        let base = env["XDG_CONFIG_HOME"].flatMap { $0.isEmpty ? nil : $0 }
            ?? (NSHomeDirectory() as NSString).appendingPathComponent(".config")
        return (base as NSString).appendingPathComponent("cmagic/config.toml")
    }

    /// Load the configuration from `path` (defaults to ``defaultPath``).
    /// Throws ``CodemagicError`` when the file or token is missing.
    public static func load(path: String = defaultPath) throws -> CmagicConfig {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else {
            throw CodemagicError.configFileMissing(path: path)
        }
        warnIfPermissive(path: path, fileManager: fm)

        let contents = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        guard let token = parseValue(for: "token", in: contents), !token.isEmpty else {
            throw CodemagicError.tokenMissing(path: path)
        }
        return CmagicConfig(token: token)
    }

    // MARK: - Minimal TOML

    /// Extract a top-level `key = "value"` (or bare `key = value`) from TOML text,
    /// ignoring comments and whitespace. Enough for this flat config file.
    static func parseValue(for key: String, in toml: String) -> String? {
        for rawLine in toml.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.hasPrefix("#") else { continue }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let name = line[..<eq].trimmingCharacters(in: .whitespaces)
            guard name == key else { continue }
            var value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if let hash = value.firstIndex(of: "#"), !value.hasPrefix("\"") {
                value = String(value[..<hash]).trimmingCharacters(in: .whitespaces)
            }
            if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            return value
        }
        return nil
    }

    private static func warnIfPermissive(path: String, fileManager fm: FileManager) {
        guard let attrs = try? fm.attributesOfItem(atPath: path),
              let perms = (attrs[.posixPermissions] as? NSNumber)?.uint16Value else { return }
        if perms & 0o077 != 0 {
            FileHandle.standardError.write(
                Data("warning: \(path) is group/world-readable; run `chmod 600 \(path)`\n".utf8)
            )
        }
    }
}
