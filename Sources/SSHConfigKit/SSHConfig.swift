import Foundation

/// A single `Key value` line inside a `Host` block.
public struct Directive: Equatable, Identifiable {
    public let id = UUID()
    public var key: String
    public var value: String

    public init(_ key: String, _ value: String) {
        self.key = key
        self.value = value
    }
}

/// The fields the GUI can edit for one host.
public struct SSHHost: Equatable, Identifiable {
    public let id = UUID()
    /// The `Host` line patterns. Normally one alias, e.g. `["gamma"]`.
    public var patterns: [String]
    public var hostName: String
    public var user: String
    public var port: String
    public var identityFile: String
    /// Directives we don't surface as fields, kept so nothing is dropped.
    public var extra: [Directive]

    public init(
        alias: String = "",
        patterns: [String] = [],
        hostName: String = "",
        user: String = "",
        port: String = "",
        identityFile: String = "",
        extra: [Directive] = []
    ) {
        self.patterns = patterns.isEmpty ? (alias.isEmpty ? [] : [alias]) : patterns
        self.hostName = hostName
        self.user = user
        self.port = port
        self.identityFile = identityFile
        self.extra = extra
    }

    /// First pattern; what you type after `ssh`.
    public var alias: String {
        get { patterns.first ?? "" }
        set {
            if patterns.isEmpty { patterns = [newValue] } else { patterns[0] = newValue }
        }
    }

    /// `Host *` and friends are config defaults, not connectable hosts.
    public var isWildcard: Bool {
        patterns.contains { $0.contains("*") || $0.contains("?") }
    }

    public var subtitle: String {
        var parts: [String] = []
        if !user.isEmpty || !hostName.isEmpty {
            parts.append("\(user.isEmpty ? "" : user + "@")\(hostName)")
        }
        if !port.isEmpty { parts.append("port \(port)") }
        return parts.joined(separator: "  ·  ")
    }

    /// Every field as one string, so search can match alias, user, hostname,
    /// port, key path and any extra directive.
    public var searchableText: String {
        var parts = patterns
        parts.append(contentsOf: [hostName, user, port, identityFile])
        for directive in extra {
            parts.append(directive.key)
            parts.append(directive.value)
        }
        return parts.joined(separator: " ")
    }

    /// True when every whitespace-separated token in `query` appears somewhere
    /// in the host (so `root web` matches a host with both).
    public func matches(_ query: String) -> Bool {
        let tokens = query.lowercased().split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard !tokens.isEmpty else { return true }
        let haystack = searchableText.lowercased()
        return tokens.allSatisfy { haystack.contains($0) }
    }
}

/// Round-trip-safe reader/writer for `~/.ssh/config`.
///
/// Everything the editor does not touch (comments, blank lines, `Include`,
/// `Host *` defaults) is preserved byte-for-byte.
public struct SSHConfigDocument {
    public private(set) var lines: [String]

    public init(text: String) {
        self.lines = text.isEmpty ? [] : text.components(separatedBy: "\n")
    }

    public var text: String { lines.joined(separator: "\n") }

    // MARK: Reading

    public func hosts() -> [SSHHost] {
        blocks().map(parse).filter { !$0.isWildcard && !$0.alias.isEmpty }
    }

    /// All patterns declared across every block, for duplicate checks.
    public func aliases() -> [String] {
        blocks().map(parse).filter { !$0.isWildcard }.map(\.alias)
    }

    // MARK: Writing

    /// Insert a new host, or replace the block whose `Host` patterns contain
    /// `host.alias`. Leaves every other byte of the file alone.
    public mutating func upsert(_ host: SSHHost) {
        guard !host.alias.isEmpty else { return }
        let new = render(host)
        if let block = blocks().first(where: { parse($0).patterns.contains(host.alias) }) {
            lines.replaceSubrange(block.header...block.bodyEnd, with: new)
        } else {
            if let last = lines.last, !last.trimmingCharacters(in: .whitespaces).isEmpty {
                lines.append("")
            }
            lines.append(contentsOf: new)
        }
    }

    @discardableResult
    public mutating func remove(alias: String) -> Bool {
        guard let block = blocks().first(where: { parse($0).patterns.contains(alias) }) else {
            return false
        }
        lines.removeSubrange(block.header...block.regionEnd)
        // Collapse a blank line left behind next to an existing blank line.
        if block.header > 0, block.header < lines.count,
           lines[block.header - 1].trimmingCharacters(in: .whitespaces).isEmpty,
           lines[block.header].trimmingCharacters(in: .whitespaces).isEmpty {
            lines.remove(at: block.header)
        }
        return true
    }

    // MARK: Parsing internals

    /// A `Host …` line through the line before the next `Host`/`Include`.
    /// `bodyEnd` is the last real directive line, so trailing blank/comment
    /// lines stay outside the block and survive edits verbatim.
    private struct Block {
        var header: Int
        var bodyEnd: Int
        var regionEnd: Int
    }

    private static func isHostHeader(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        return t == "Host" || t.hasPrefix("Host ") || t.hasPrefix("Host\t")
    }

    private static func isBoundary(_ line: String) -> Bool {
        if isHostHeader(line) { return true }
        let t = line.trimmingCharacters(in: .whitespaces)
        return t == "Include" || t.hasPrefix("Include ") || t.hasPrefix("Include\t")
    }

    private func blocks() -> [Block] {
        var out: [Block] = []
        var i = 0
        while i < lines.count {
            guard Self.isHostHeader(lines[i]) else { i += 1; continue }
            var j = i + 1
            while j < lines.count && !Self.isBoundary(lines[j]) { j += 1 }
            var bodyEnd = i
            if j - 1 >= i + 1 {
                for k in stride(from: j - 1, through: i + 1, by: -1) {
                    let t = lines[k].trimmingCharacters(in: .whitespaces)
                    if !t.isEmpty && !t.hasPrefix("#") { bodyEnd = k; break }
                }
            }
            out.append(Block(header: i, bodyEnd: bodyEnd, regionEnd: j - 1))
            i = j
        }
        return out
    }

    private func parse(_ block: Block) -> SSHHost {
        let header = lines[block.header].trimmingCharacters(in: .whitespaces)
        var patterns = header
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .dropFirst()
            .map(String.init)
        if patterns.isEmpty { patterns = [""] }

        var host = SSHHost(patterns: patterns)
        if block.bodyEnd > block.header {
            for k in (block.header + 1)...block.bodyEnd {
                guard let (key, value) = Self.parseDirective(lines[k]) else { continue }
                switch key.lowercased() {
                case "hostname": host.hostName = value
                case "user": host.user = value
                case "port": host.port = value
                case "identityfile": host.identityFile = value
                default: host.extra.append(Directive(key, value))
                }
            }
        }
        return host
    }

    private static func parseDirective(_ line: String) -> (String, String)? {
        let t = line.trimmingCharacters(in: .whitespaces)
        if t.isEmpty || t.hasPrefix("#") { return nil }
        let parts = t.split(maxSplits: 1, whereSeparator: {
            $0 == " " || $0 == "\t" || $0 == "="
        })
        guard let key = parts.first, !key.isEmpty else { return nil }
        let value = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
        return (String(key), value)
    }

    private func render(_ host: SSHHost) -> [String] {
        let patterns = host.patterns.isEmpty ? [host.alias] : host.patterns
        var out = ["Host " + patterns.joined(separator: " ")]
        func add(_ key: String, _ value: String) {
            guard !value.isEmpty else { return }
            out.append("\t\(key) \(value)")
        }
        add("HostName", host.hostName)
        add("User", host.user)
        add("Port", host.port)
        add("IdentityFile", host.identityFile)
        for directive in host.extra where !directive.key.isEmpty {
            out.append("\t\(directive.key) \(directive.value)")
        }
        return out
    }
}
