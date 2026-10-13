# SSH Config Manager

A small, native macOS app (SwiftUI) for editing `~/.ssh/config` — plus a tiny
CLI, `sshls`, for listing hosts from the terminal. Both share one library, so
they behave identically.

Add a host, give it an alias, set `HostName` / `User` / `Port` / `IdentityFile`,
save. Then just `ssh myserver`.

There is no Xcode project — it's a Swift Package and builds with the Command
Line Tools alone.

## Features

- **Native SwiftUI GUI** — list, search, add, edit and delete hosts.
- **Round-trip-safe writes** — `Include` lines, comments, blank lines and the
  `Host *` defaults block survive byte-for-byte. Only the host block you edit is
  rewritten.
- **Append-only history** — every save is snapshotted to
  `~/.ssh/config.history/`, so a bad edit can never destroy a good one.
  Restores are non-destructive and themselves undoable.
- **`sshls` CLI** — pipe-friendly host listing with the same search matching as
  the GUI.
- **Safe by default** — saved files keep `0600` permissions.

## Requirements

- macOS 14 or later
- Swift 5.9 toolchain (Command Line Tools are enough — no Xcode project)

## Run (development)

```sh
swift run SSHConfigManager
```

## Build a double-clickable app

```sh
./make-app.sh
open ".build/SSH Config Manager.app"
```

## Tests

Plain assert checks, no test framework needed:

```sh
swift run SSHConfigKitChecks
```

## How it touches your file

- Writes to the real `~/.ssh/config`.
- Re-applies `0600` permissions on save.
- Round-trip-safe: `Include` lines, comments, blank lines and the `Host *`
  defaults block are preserved byte-for-byte. Only the `Host` block you edit is
  rewritten.
- Wildcard `Host` patterns (`*`, `?`) are config defaults, not connectable
  hosts — kept in the file but hidden from lists.

## Version history (no data loss)

Every save writes a new version to `~/.ssh/config.history/` (directory mode
`0700`, files `0600`). Nothing is ever overwritten or deleted, so a bad edit
can't destroy an earlier good one.

- Filenames: `2026-10-12_11-22-33.456~add myserver.conf`
- The first launch stores the untouched file as `original`.
- Restoring is non-destructive: the current file is snapshotted first, so you
  can undo a restore too.
- Identical consecutive content isn't stored twice.
- In the app: click the **History** clock icon to browse versions grouped by
  day and restore any of them.

History grows forever by design. If it gets large, prune
`~/.ssh/config.history/` manually (old files are safe to delete).

## CLI: `sshls`

The app and the CLI share the same `SSHConfigKit`, so they match identically.

```sh
swift run sshls              # all aliases, one per line
swift run sshls cov          # filter (same rules as the GUI)
swift run sshls -v root      # alias + user@host · port
swift run sshls -h           # help
```

Install it on your `PATH` (needs `sudo` once, since `/usr/local/bin` is
root-owned):

```sh
swift build -c release
sudo install -m 0755 "$(swift build -c release --show-bin-path)/sshls" /usr/local/bin/sshls
```

Set `SSH_CONFIG=/path/to/file` to point it at a different config.

## Tab completion after `ssh` (already works)

`ssh cov<tab>` completes from `~/.ssh/config` out of the box — zsh's built-in
`_ssh_hosts` reads that file directly. The app writes the same file, so new
hosts complete as soon as they're saved. No extra tool needed.

To also complete `sshls`'s arguments, add to `~/.zshrc`:

```zsh
_sshls() { compadd -- ${(f)"$(command sshls $words[2,-1] 2>/dev/null)"} }
compdef _sshls sshls
```

Optional: if you want `ssh ls` itself to list hosts, wrap ssh (this shadows the
real command, so only do it if you're comfortable with that):

```zsh
ssh() { if [[ $1 == ls ]]; then shift; command sshls "$@"; else command ssh "$@"; fi }
```

## Project layout

```
Sources/
  SSHConfigKit/        shared library: model, parser/writer, history
  SSHConfigManager/    SwiftUI app (@main, ConfigStore, views)
  sshls/               CLI: prints host aliases, one per line
  SSHConfigKitChecks/  the test suite (plain asserts)
```

## Known limits (by design, add when needed)

- `Host *` / wildcard blocks are hidden from the list (they're defaults, not
  connectable servers) but left untouched in the file.
- Only HostName / User / Port / IdentityFile have fields. Other directives in a
  host block (e.g. `ProxyJump`) are preserved as-is and shown read-only; you
  can't edit them in the GUI yet.
- A comment placed *inside* a host block, between directives, is not preserved
  when you edit that specific host.

## License

[MIT](LICENSE)
