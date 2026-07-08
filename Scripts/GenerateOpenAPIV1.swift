#!/usr/bin/env swift
//
// GenerateOpenAPIV1.swift
//
// Converts the downloaded Codemagic v1 REST API HTML docs into an OpenAPI 3.1
// document. Codemagic publishes no machine-readable spec for the v1 API, so this
// script scrapes the human docs (documentation/v1-api-docs/*.html) and emits a
// spec that swift-openapi-generator can consume.
//
// What it extracts reliably: operations (METHOD + path), a summary (the <h2>
// heading), and request parameters (the "Parameters" <table>). Response bodies
// are NOT documented as schemas in the HTML, so responses are emitted as generic
// open objects (additionalProperties: true); tighten them by hand or against live
// samples afterwards.
//
// Usage:
//   swift Scripts/GenerateOpenAPIV1.swift [docsDir] [outputFile]
// Defaults:
//   docsDir    = documentation/v1-api-docs
//   outputFile = documentation/openapi-v1.generated.json
//
import Foundation

// MARK: - Arguments

let args = CommandLine.arguments
let docsDir = args.count > 1 ? args[1] : "documentation/v1-api-docs"
let outputFile = args.count > 2 ? args[2] : "documentation/openapi-v1.generated.json"

// MARK: - HTML helpers

func regexMatches(_ pattern: String, in text: String) -> [NSTextCheckingResult] {
    let re = try! NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive])
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    return re.matches(in: text, options: [], range: range)
}

func group(_ m: NSTextCheckingResult, _ i: Int, in text: String) -> String? {
    guard i < m.numberOfRanges, let r = Range(m.range(at: i), in: text) else { return nil }
    return String(text[r])
}

func stripTags(_ s: String) -> String {
    let noTags = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    return decodeEntities(noTags).trimmingCharacters(in: .whitespacesAndNewlines)
}

func decodeEntities(_ s: String) -> String {
    var out = s
    let map = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&nbsp;": " "]
    for (k, v) in map { out = out.replacingOccurrences(of: k, with: v) }
    return out
}

// MARK: - Model

struct Parameter {
    let name: String
    let type: String
    let description: String
    let required: Bool
}

struct Operation {
    let method: String        // lowercased
    let path: String          // OpenAPI-style, ":id" -> "{id}"
    let summary: String
    let pathParams: [String]
    let otherParams: [Parameter]
    let tag: String
}

// MARK: - Parsing

/// Convert a documented path (":id", "/public-url") into an OpenAPI template path.
func normalizePath(_ raw: String) -> (path: String, params: [String]) {
    var params: [String] = []
    let segments = raw.split(separator: "/", omittingEmptySubsequences: false).map { seg -> String in
        if seg.hasPrefix(":") {
            let name = String(seg.dropFirst())
            params.append(name)
            return "{\(name)}"
        }
        return String(seg)
    }
    return (segments.joined(separator: "/"), params)
}

func parseParameters(fromTable table: String) -> [Parameter] {
    var params: [Parameter] = []
    for row in regexMatches("<tr\\b[^>]*>(.*?)</tr>", in: table) {
        guard let inner = group(row, 1, in: table) else { continue }
        if inner.range(of: "<th", options: .caseInsensitive) != nil { continue } // header row
        let cells = regexMatches("<td\\b[^>]*>(.*?)</td>", in: inner).compactMap { group($0, 1, in: inner).map(stripTags) }
        guard cells.count >= 3 else { continue }
        let desc = cells[2]
        let required = desc.lowercased().hasPrefix("required")
        params.append(Parameter(name: cells[0], type: cells[1], description: desc, required: required))
    }
    return params
}

func parse(file: String, tag: String) -> [Operation] {
    guard let html = try? String(contentsOfFile: file, encoding: .utf8) else { return [] }
    let ns = html as NSString

    // Section boundaries: each <h2> starts one operation.
    let h2s = regexMatches("<h2\\b[^>]*>(.*?)</h2>", in: html)
    var ops: [Operation] = []
    for (idx, h2) in h2s.enumerated() {
        let start = h2.range.location
        let end = idx + 1 < h2s.count ? h2s[idx + 1].range.location : ns.length
        let section = ns.substring(with: NSRange(location: start, length: end - start))
        let summary = group(h2, 1, in: html).map(stripTags) ?? ""

        // First METHOD + path inside the section.
        guard let mp = regexMatches("\\b(GET|POST|PUT|PATCH|DELETE)\\s+(/[^<\\s\"']+)", in: section).first,
              let method = group(mp, 1, in: section)?.lowercased(),
              let rawPath = group(mp, 2, in: section) else { continue }
        let (path, pathParams) = normalizePath(rawPath)

        // First parameter table inside the section, if any.
        var otherParams: [Parameter] = []
        if let table = regexMatches("<table\\b[^>]*>(.*?)</table>", in: section).first,
           let tableHTML = group(table, 1, in: section) {
            let all = parseParameters(fromTable: tableHTML)
            // Params already expressed in the path are path params; the rest are query/body.
            otherParams = all.filter { !pathParams.contains($0.name) }
        }
        ops.append(Operation(method: method, path: path, summary: summary,
                             pathParams: pathParams, otherParams: otherParams, tag: tag))
    }
    return ops
}

// MARK: - OpenAPI assembly

func operationId(_ op: Operation) -> String {
    let parts = op.path.split(separator: "/").map { seg -> String in
        seg.replacingOccurrences(of: "{", with: "").replacingOccurrences(of: "}", with: "")
    }
    let camel = parts.enumerated().map { i, s in i == 0 ? s : s.prefix(1).uppercased() + s.dropFirst() }.joined()
    return op.method + camel.prefix(1).uppercased() + camel.dropFirst()
}

func schema(for type: String) -> [String: Any] {
    switch type.lowercased() {
    case "integer", "number": return ["type": "integer"]
    case "boolean": return ["type": "boolean"]
    case "list", "array": return ["type": "array", "items": ["type": "string"]]
    case "object": return ["type": "object", "additionalProperties": true]
    default: return ["type": "string"]
    }
}

func openAPIObject(_ ops: [Operation]) -> [String: Any] {
    var paths: [String: [String: Any]] = [:]
    let genericResponse: [String: Any] = [
        "description": "Success",
        "content": ["application/json": ["schema": ["type": "object", "additionalProperties": true]]],
    ]

    for op in ops {
        var operation: [String: Any] = [
            "tags": [op.tag],
            "operationId": operationId(op),
            "summary": op.summary,
        ]

        var parameters: [[String: Any]] = []
        for name in op.pathParams {
            parameters.append(["name": name, "in": "path", "required": true, "schema": ["type": "string"]])
        }

        if op.method == "get" || op.method == "delete" {
            for p in op.otherParams {
                parameters.append(["name": p.name, "in": "query", "required": p.required,
                                   "description": p.description, "schema": schema(for: p.type)])
            }
        } else if !op.otherParams.isEmpty {
            var props: [String: Any] = [:]
            var required: [String] = []
            for p in op.otherParams {
                props[p.name] = schema(for: p.type).merging(["description": p.description]) { a, _ in a }
                if p.required { required.append(p.name) }
            }
            var bodySchema: [String: Any] = ["type": "object", "properties": props]
            if !required.isEmpty { bodySchema["required"] = required }
            operation["requestBody"] = [
                "required": true,
                "content": ["application/json": ["schema": bodySchema]],
            ]
        }
        if !parameters.isEmpty { operation["parameters"] = parameters }

        var responses: [String: Any] = ["200": genericResponse]
        if op.path.hasSuffix("/cancel") { responses["208"] = ["description": "Already Reported — build already finished"] }
        if op.method == "delete" { responses = ["202": ["description": "Accepted — processed asynchronously"]] }
        operation["responses"] = responses

        paths[op.path, default: [:]][op.method] = operation
    }

    return [
        "openapi": "3.1.0",
        "info": [
            "title": "Codemagic REST API (v1, generated)",
            "version": "1.0.0",
            "description": "Generated from the Codemagic v1 HTML docs by Scripts/GenerateOpenAPIV1.swift. "
                + "Response bodies are open objects; tighten against live samples.",
        ],
        "servers": [["url": "https://api.codemagic.io"]],
        "security": [["apiToken": []]],
        "components": [
            "securitySchemes": [
                "apiToken": ["type": "apiKey", "in": "header", "name": "x-auth-token"],
            ],
        ],
        "paths": paths,
    ]
}

// MARK: - Main

let pages: [(file: String, tag: String)] = [
    ("applications.html", "Applications"),
    ("builds.html", "Builds"),
    ("artifacts.html", "Artifacts"),
    ("caches.html", "Caches"),
]

var operations: [Operation] = []
for page in pages {
    let path = "\(docsDir)/\(page.file)"
    let ops = parse(file: path, tag: page.tag)
    FileHandle.standardError.write("parsed \(ops.count) operation(s) from \(page.file)\n".data(using: .utf8)!)
    operations.append(contentsOf: ops)
}

guard !operations.isEmpty else {
    FileHandle.standardError.write("error: no operations parsed — check docsDir '\(docsDir)'\n".data(using: .utf8)!)
    exit(1)
}

let spec = openAPIObject(operations)
let data = try JSONSerialization.data(withJSONObject: spec, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
try data.write(to: URL(fileURLWithPath: outputFile))
FileHandle.standardError.write("wrote \(operations.count) operations to \(outputFile)\n".data(using: .utf8)!)
