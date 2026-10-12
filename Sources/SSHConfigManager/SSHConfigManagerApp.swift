import SwiftUI
import SSHConfigKit

@main
struct SSHConfigManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = ConfigStore()

    var body: some Scene {
        WindowGroup("SSH Config Manager") {
            ContentView().environmentObject(store)
        }
    }
}

/// Only matters when launched as a bare binary (`swift run`) instead of a
/// bundled .app: gives the window focus and a normal app menu.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
final class ConfigStore: ObservableObject {
    @Published var hosts: [SSHHost] = []
    @Published var snapshots: [ConfigSnapshot] = []
    @Published var status: String = ""
    @Published var loadError: String?

    private var doc = SSHConfigDocument(text: "")
    let url: URL
    let history: ConfigHistory

    init() {
        let sshDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ssh")
        url = sshDir.appendingPathComponent("config")
        history = ConfigHistory(directory: sshDir.appendingPathComponent("config.history"))
        load()
    }

    func load() {
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            doc = SSHConfigDocument(text: text)
            loadError = nil
            // First run: capture the untouched file so "original" is always restorable.
            if history.snapshots().isEmpty {
                _ = try? history.record(text: text, label: "original")
            }
            status = "Loaded \(doc.hosts().count) hosts from \(url.path)"
        } catch {
            doc = SSHConfigDocument(text: "")
            loadError = "Could not read \(url.path): \(error.localizedDescription)"
            status = loadError ?? ""
        }
        hosts = doc.hosts()
        snapshots = history.snapshots()
    }

    func upsert(_ host: SSHHost) {
        let existed = hosts.contains { $0.alias == host.alias }
        doc.upsert(host)
        hosts = doc.hosts()
        persist(label: existed ? "edit \(host.alias)" : "add \(host.alias)")
    }

    func remove(_ host: SSHHost) {
        guard doc.remove(alias: host.alias) else { return }
        hosts = doc.hosts()
        persist(label: "remove \(host.alias)")
    }

    /// Non-destructive: the current file is snapshotted first, so a restore is
    /// itself undoable.
    func restore(_ snapshot: ConfigSnapshot) {
        guard let text = try? history.text(of: snapshot) else {
            status = "Could not read that version"
            return
        }
        _ = try? history.record(text: doc.text, label: "before restore")
        doc = SSHConfigDocument(text: text)
        hosts = doc.hosts()
        writeFile()
        _ = try? history.record(text: text, label: "restore")
        snapshots = history.snapshots()
        status = "Restored version from \(snapshot.date.formatted(date: .abbreviated, time: .standard))"
    }

    private func persist(label: String) {
        writeFile()
        _ = try? history.record(text: doc.text, label: label)
        snapshots = history.snapshots()
        status = "Saved · \(hosts.count) hosts"
    }

    private func writeFile() {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try doc.text.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: url.path
            )
        } catch {
            status = "Save failed: \(error.localizedDescription)"
        }
    }
}
