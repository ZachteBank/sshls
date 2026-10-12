import Foundation
import SSHConfigKit

// sshls — list the hosts in ~/.ssh/config.
//
//   sshls                 all aliases, one per line (pipes into fzf/scripts)
//   sshls cov             filter, same matching rules as the GUI
//   sshls -v              alias + user@host · port
//   sshls -h              help

let fm = FileManager.default
let url: URL = ProcessInfo.processInfo.environment["SSH_CONFIG"]
    .map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
    ?? fm.homeDirectoryForCurrentUser.appendingPathComponent(".ssh/config")
let args = Array(CommandLine.arguments.dropFirst())

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("sshls: \(message)\n".utf8))
    exit(1)
}

if args.contains("-h") || args.contains("--help") {
    print("""
    Usage: sshls [-v] [query…]

    Lists Host aliases from ~/.ssh/config. A query filters like the GUI:
    every word must appear somewhere in the host (alias, user, hostname,
    port, key path). Wildcard blocks like `Host *` are excluded.
    """)
    exit(0)
}

let verbose = args.contains("-v") || args.contains("--verbose")
let query = args.filter { !$0.hasPrefix("-") }.joined(separator: " ")

guard let text = try? String(contentsOf: url, encoding: .utf8) else {
    fail("cannot read \(url.path)")
}

for host in SSHConfigDocument(text: text).hosts().filter({ $0.matches(query) }) {
    print(verbose && !host.subtitle.isEmpty ? "\(host.alias)\t\(host.subtitle)" : host.alias)
}
