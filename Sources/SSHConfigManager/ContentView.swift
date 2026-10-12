import SwiftUI
import SSHConfigKit

struct ContentView: View {
    @EnvironmentObject private var store: ConfigStore
    @State private var editing: SSHHost?
    @State private var showingHistory = false
    @State private var query = ""

    private var filteredHosts: [SSHHost] {
        store.hosts.filter { $0.matches(query) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredHosts) { host in
                    row(host)
                }
            }
            .searchable(text: $query, prompt: "Search alias, host, user, port…")
            .overlay {
                if store.hosts.isEmpty {
                    ContentUnavailableView(
                        "No hosts",
                        systemImage: "server.rack",
                        description: Text(store.loadError ?? "Add one with the + button.")
                    )
                } else if filteredHosts.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .navigationTitle("SSH Hosts")
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Text(store.status).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(8)
            }
            .toolbar {
                ToolbarItem {
                    Button { store.load() } label: {
                        Label("Reload", systemImage: "arrow.clockwise")
                    }
                }
                ToolbarItem {
                    Button { showingHistory = true } label: {
                        Label("History", systemImage: "clock.arrow.circlepath")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { editing = SSHHost() } label: {
                        Label("Add Host", systemImage: "plus")
                    }
                }
            }
            .sheet(item: $editing) { host in
                HostEditor(original: host).environmentObject(store)
            }
            .sheet(isPresented: $showingHistory) {
                HistoryView().environmentObject(store)
            }
        }
        .frame(minWidth: 520, minHeight: 420)
    }

    private func row(_ host: SSHHost) -> some View {
        HStack {
            Image(systemName: "server.rack").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(host.alias).font(.headline)
                if !host.subtitle.isEmpty {
                    Text(host.subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture { editing = host }
        .contextMenu {
            Button("Edit") { editing = host }
            Button("Copy “ssh \(host.alias)”") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("ssh \(host.alias)", forType: .string)
                store.status = "Copied: ssh \(host.alias)"
            }
            Divider()
            Button("Delete", role: .destructive) { store.remove(host) }
        }
    }
}

struct HostEditor: View {
    @EnvironmentObject private var store: ConfigStore
    @Environment(\.dismiss) private var dismiss
    @State private var host: SSHHost
    private let isNew: Bool

    init(original: SSHHost) {
        _host = State(initialValue: original)
        isNew = original.alias.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isNew ? "New Host" : "Edit “\(host.alias)”").font(.title2).bold()

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 8) {
                field("Alias", $host.alias, "gamma")
                field("HostName", $host.hostName, "gamma.example.com")
                field("User", $host.user, "root")
                field("Port", $host.port, "22")
                field("IdentityFile", $host.identityFile, "~/.ssh/id_rsa")
            }

            if !host.extra.isEmpty {
                Text("Kept as-is: " + host.extra.map { "\($0.key) \($0.value)" }.joined(separator: ", "))
                    .font(.caption).foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(host.alias.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private func field(_ label: String, _ text: Binding<String>, _ prompt: String) -> some View {
        GridRow {
            Text(label).gridColumnAlignment(.trailing).foregroundStyle(.secondary)
            TextField(prompt, text: text).textFieldStyle(.roundedBorder).frame(width: 300)
        }
    }

    private func save() {
        host.alias = host.alias.trimmingCharacters(in: .whitespaces)
        store.upsert(host)
        dismiss()
    }
}

struct HistoryView: View {
    @EnvironmentObject private var store: ConfigStore
    @Environment(\.dismiss) private var dismiss

    /// Newest day first, snapshots within a day newest first.
    private var days: [(day: Date, items: [ConfigSnapshot])] {
        Dictionary(grouping: store.snapshots) { Calendar.current.startOfDay(for: $0.date) }
            .map { (day: $0.key, items: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.day > $1.day }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Version History").font(.title2).bold()
                Spacer()
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([store.history.directory])
                }
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            if store.snapshots.isEmpty {
                ContentUnavailableView(
                    "No versions yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Every edit is saved as a new version automatically.")
                )
            } else {
                List {
                    ForEach(days, id: \.day) { group in
                        Section(group.day.formatted(date: .complete, time: .omitted)) {
                            ForEach(group.items) { snapshot in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(snapshot.displayLabel)
                                        Text(snapshot.date.formatted(date: .omitted, time: .standard))
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button("Restore") { store.restore(snapshot) }
                                }
                            }
                        }
                    }
                }
            }
        }
        .frame(width: 480, height: 520)
    }
}
