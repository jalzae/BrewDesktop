import SwiftUI

struct PackageDetailView: View {
    @EnvironmentObject var store: BrewStore
    let pkg: PackageEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                HStack {
                    if pkg.outdated {
                        Button {
                            store.upgrade([pkg.name])
                        } label: {
                            Label("Upgrade", systemImage: "arrow.up.circle")
                        }
                    }
                    Button {
                        store.reinstall(pkg)
                    } label: {
                        Label("Reinstall", systemImage: "arrow.triangle.2.circlepath")
                    }
                    if pkg.kind == .formula {
                        Button {
                            store.setPinned(pkg, pinned: !pkg.pinned)
                        } label: {
                            Label(pkg.pinned ? "Unpin" : "Pin", systemImage: pkg.pinned ? "pin.slash" : "pin")
                        }
                    }
                    Spacer()
                    Button(role: .destructive) {
                        store.uninstall(pkg)
                    } label: {
                        Label("Uninstall", systemImage: "trash")
                    }
                }
                .padding(.vertical, 4)

                GroupBox("Details") {
                    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                        GridRow {
                            Text("Version").foregroundStyle(.secondary)
                            Text(pkg.version).font(.body.monospaced()).textSelection(.enabled)
                        }
                        GridRow {
                            Text("Tap").foregroundStyle(.secondary)
                            Text(pkg.tap).font(.body.monospaced())
                        }
                        GridRow {
                            Text("Kind").foregroundStyle(.secondary)
                            Text(pkg.kind == .cask ? "Cask" : "Formula")
                        }
                        GridRow {
                            Text("Installed as").foregroundStyle(.secondary)
                            Text(pkg.installedOnRequest ? "requested" : "dependency")
                        }
                        if let date = pkg.installedTime {
                            GridRow {
                                Text("Installed at").foregroundStyle(.secondary)
                                Text(date.formatted(date: .abbreviated, time: .shortened))
                            }
                        }
                        GridRow {
                            Text("Homepage").foregroundStyle(.secondary)
                            if let url = URL(string: pkg.homepage), !pkg.homepage.isEmpty {
                                Link(pkg.homepage, destination: url).lineLimit(1)
                            } else {
                                Text("—")
                            }
                        }
                        GridRow {
                            Text("Service").foregroundStyle(.secondary)
                            if pkg.hasService {
                                let entry = store.services.first { $0.name == pkg.name }
                                HStack(spacing: 6) {
                                    if let entry {
                                        StatusDot(status: entry.status)
                                        Text(entry.status.label)
                                    } else {
                                        Text("supported")
                                    }
                                    Button("Start") {
                                        if let entry {
                                            store.service("start", entry)
                                        } else {
                                            store.service("start", ServiceEntry(name: pkg.name, status: .none_, user: nil, file: nil, exitCode: nil))
                                        }
                                    }
                                    .controlSize(.small)
                                }
                            } else {
                                Text("—")
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                }

                if !pkg.dependencies.isEmpty {
                    GroupBox("Dependencies (\(pkg.dependencies.count))") {
                        FlowLayout(deps: pkg.dependencies)
                            .padding(6)
                    }
                }

                if let caveats = pkg.caveats, !caveats.isEmpty {
                    GroupBox("Caveats") {
                        Text(caveats)
                            .font(.system(size: 12, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(6)
                    }
                }
            }
            .padding(16)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(pkg.name).font(.title2.weight(.bold))
                Text(pkg.version).font(.title3.monospaced()).foregroundStyle(.secondary)
                if pkg.outdated { Badge("outdated", color: .orange) }
                if pkg.pinned { Badge("pinned", color: .orange) }
                if pkg.deprecated { Badge("deprecated", color: .red) }
            }
            if !pkg.desc.isEmpty {
                Text(pkg.desc).foregroundStyle(.secondary)
            }
        }
    }
}

// Simple wrapping chip layout for dependency names.
struct FlowLayout: View {
    let deps: [String]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(deps, id: \.self) { dep in
                Text(dep)
                    .font(.caption.monospaced())
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
                    .lineLimit(1)
            }
        }
    }
}
