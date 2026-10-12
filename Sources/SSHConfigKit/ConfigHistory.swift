import Foundation

/// One stored version of the config file.
public struct ConfigSnapshot: Identifiable, Equatable {
    /// Filename, unique per snapshot.
    public let id: String
    public let url: URL
    public let date: Date
    /// What change produced it, e.g. "add gamma".
    public let label: String

    public var displayLabel: String { label.isEmpty ? "edit" : label }
}

/// Append-only version store for `~/.ssh/config`.
///
/// Every save writes a new timestamped file; nothing is ever overwritten or
/// deleted, so no edit (even a bad one) can destroy an earlier good version.
public struct ConfigHistory {
    public let directory: URL
    private let fm = FileManager.default

    public init(directory: URL) {
        self.directory = directory
    }

    /// Filename stamps sort lexicographically and parse back to a Date.
    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss.SSS"
        return f
    }()

    /// Newest first.
    public func snapshots() -> [ConfigSnapshot] {
        let urls = (try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        return urls
            .filter { $0.pathExtension == "conf" }
            .compactMap { url -> ConfigSnapshot? in
                let name = url.deletingPathExtension().lastPathComponent
                guard let sep = name.firstIndex(of: "~") else { return nil }
                let stampText = String(name[name.startIndex..<sep])
                let label = String(name[name.index(after: sep)...])
                guard let date = Self.stamp.date(from: stampText) else { return nil }
                return ConfigSnapshot(id: name, url: url, date: date, label: label)
            }
            .sorted { $0.date == $1.date ? $0.id > $1.id : $0.date > $1.date }
    }

    /// Store `text` as a new version. Returns the snapshot, or `nil` when the
    /// most recent version already has identical content (nothing to record).
    @discardableResult
    public func record(text: String, label: String) throws -> ConfigSnapshot? {
        if let latest = snapshots().first,
           (try? String(contentsOf: latest.url, encoding: .utf8)) == text {
            return nil
        }

        try fm.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let safe = label
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "~", with: "-")
            .replacingOccurrences(of: "\n", with: " ")
        var base = "\(Self.stamp.string(from: Date()))~\(safe)"
        var url = directory.appendingPathComponent(base).appendingPathExtension("conf")
        var n = 1
        while fm.fileExists(atPath: url.path) {
            n += 1
            base = "\(Self.stamp.string(from: Date()))~\(safe)-\(n)"
            url = directory.appendingPathComponent(base).appendingPathExtension("conf")
        }

        try text.write(to: url, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return ConfigSnapshot(id: base, url: url, date: Date(), label: safe)
    }

    public func text(of snapshot: ConfigSnapshot) throws -> String {
        try String(contentsOf: snapshot.url, encoding: .utf8)
    }
}
