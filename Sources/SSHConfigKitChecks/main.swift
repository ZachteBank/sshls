import Foundation
import SSHConfigKit

// Run with: swift run SSHConfigKitChecks
// Plain asserts, no test framework, so it runs with Command Line Tools alone.

var failures = 0
func check(_ passed: Bool, _ label: String) {
    print(passed ? "  ok   \(label)" : "FAIL   \(label)")
    if !passed { failures += 1 }
}

// Mirrors the messiness of a real config: Include, comments, mixed
// tabs/spaces, a `Host *` defaults block.
let fixture = [
    "Include ~/.ssh/config.d/extra",
    "",
    "Host alpha",
    "\tUser admin",
    "\tHostName 192.0.2.10",
    "",
    "# IdentityFile ~/.ssh/id_rsa",
    "Host beta",
    "\tUser deploy",
    "\tHostName beta.example.com",
    "\tPort 2222",
    "",
    "Host *",
    "\tUseKeychain yes",
    "",
    "Host gamma",
    "  HostName gamma.example.com",
    "  User root",
    "  IdentityFile ~/.ssh/id_rsa",
].joined(separator: "\n")

// 1. Reading then writing with no edits must not change a single byte.
check(SSHConfigDocument(text: fixture).text == fixture, "round trip is byte-identical")

// 2. Parse hosts, skip the wildcard defaults block.
let hosts = SSHConfigDocument(text: fixture).hosts()
check(hosts.map(\.alias) == ["alpha", "beta", "gamma"], "parses 3 hosts, skips Host *")
check(hosts.first { $0.alias == "gamma" }?.user == "root", "reads User")
check(hosts.first { $0.alias == "gamma" }?.identityFile == "~/.ssh/id_rsa", "reads IdentityFile")
check(hosts.first { $0.alias == "beta" }?.port == "2222", "reads Port")

// 3. Editing one host leaves everything else untouched.
do {
    var doc = SSHConfigDocument(text: fixture)
    guard var host = doc.hosts().first(where: { $0.alias == "alpha" }) else {
        check(false, "edit: alpha not found"); exit(1)
    }
    host.hostName = "10.0.0.5"
    doc.upsert(host)
    let text = doc.text
    check(text.contains("HostName 10.0.0.5"), "edit applies change")
    check(text.contains("Include ~/.ssh/config.d/extra"), "edit keeps Include")
    check(text.contains("# IdentityFile ~/.ssh/id_rsa"), "edit keeps comment")
    check(text.contains("Host *") && text.contains("\tUseKeychain yes"), "edit keeps Host * block")
    check(doc.hosts().count == 3, "edit keeps host count")
}

// 4. Adding a host appends it without disturbing the file.
do {
    var doc = SSHConfigDocument(text: fixture)
    doc.upsert(SSHHost(alias: "web", hostName: "198.51.100.20", user: "root"))
    check(doc.hosts().count == 4, "add grows host count")
    check(doc.text.contains("Host web"), "add writes new block")
    check(doc.text.contains("Include ~/.ssh/config.d/extra"), "add keeps Include")
}

// 5. Removing a host touches only that block.
do {
    var doc = SSHConfigDocument(text: fixture)
    check(doc.remove(alias: "beta"), "remove finds host")
    check(doc.hosts().map(\.alias) == ["alpha", "gamma"], "remove drops only target")
    check(!doc.text.contains("beta"), "remove erases target text")
    check(doc.text.contains("Host gamma"), "remove keeps neighbour")
    check(doc.text.contains("Host *"), "remove keeps Host *")
    check(!doc.remove(alias: "nope"), "remove of missing host returns false")
}

// 6. History: dedupe, ordering, and reading back an old version.
do {
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("sshcfg-history-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: tmp) }

    let history = ConfigHistory(directory: tmp)
    try history.record(text: "A", label: "original")
    try history.record(text: "A", label: "no-op")
    try history.record(text: "B", label: "add gamma")

    let snaps = history.snapshots()
    check(snaps.count == 2, "history dedupes unchanged content")
    check(snaps.first?.label == "add gamma", "history lists newest first")
    check(snaps.last?.label == "original", "history keeps the original")
    check((try? history.text(of: snaps.last!)) == "A", "history reads an old version back")
    check(snaps.allSatisfy { $0.id.contains("~") }, "history filenames carry label")
}

// 7. Search matches across every field, all tokens required.
do {
    let gamma = SSHConfigDocument(text: fixture).hosts().first { $0.alias == "gamma" }!
    check(gamma.matches("gamma"), "search: alias")
    check(gamma.matches("root"), "search: user")
    check(gamma.matches("example.com"), "search: hostname substring")
    check(gamma.matches("gamma"), "search: case-insensitive")
    check(gamma.matches("root gamma"), "search: all tokens must match")
    check(!gamma.matches("gamma web"), "search: rejects non-matching token")
    check(gamma.matches("id_rsa"), "search: identity file")
    check(SSHConfigDocument(text: fixture).hosts().first { $0.alias == "beta" }!.matches("2222"),
          "search: port")
    check(gamma.matches("  "), "search: blank query matches everything")
}

print(failures == 0 ? "\nAll checks passed." : "\n\(failures) check(s) failed.")
exit(failures == 0 ? 0 : 1)
