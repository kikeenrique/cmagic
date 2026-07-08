import ArgumentParser
import Foundation

/// Shared `--json` flag + a JSON emitter, mixed into each command via `@OptionGroup`.
struct OutputOptions: ParsableArguments {
    @Flag(name: .long, help: "Emit JSON instead of human-readable text.")
    var json = false

    /// Encode `value` as pretty JSON to stdout (used when `--json` is set).
    func emit(_ value: some Encodable) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}
