import SwiftUI

// MARK: - Status dot

struct StatusDot: View {
    let status: ServiceStatus

    var color: Color {
        switch status {
        case .started: return .green
        case .scheduled: return .yellow
        case .error: return .red
        case .unknown: return .orange
        case .stopped, .none_: return .gray
        }
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .help(status.label)
    }
}

// MARK: - Badge

struct Badge: View {
    let text: String
    var color: Color = .secondary

    init(_ text: String, color: Color = .secondary) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

// MARK: - Stat tile

struct StatTile: View {
    let label: String
    let value: String
    var icon: String
    var color: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.title2.weight(.semibold))
                .lineLimit(1)
                .textSelection(.enabled)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Operation console sheet

struct ConsoleSheet: View {
    @ObservedObject var store: BrewStore

    private var op: RunningOp? { store.currentOp }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if let op {
                    Label(op.title, systemImage: op.running ? "gearshape.2" : (op.failed ? "exclamationmark.triangle" : "checkmark.circle"))
                        .font(.headline)
                }
                Spacer()
                if op?.running == true {
                    ProgressView().controlSize(.small)
                    Button("Cancel") { store.cancelOp() }
                        .controlSize(.small)
                } else {
                    Button("Done") { store.dismissConsole() }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            if let tap = store.brokenTap, op?.running != true {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                    Text("Tap `\(tap)` was removed upstream and blocks `brew update`.")
                        .font(.subheadline)
                    Spacer()
                    Button("Untap & Retry Update") {
                        store.brokenTap = nil
                        store.fixBrokenTap()
                    }
                    .controlSize(.small)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.08))
                Divider()
            }

            ScrollViewReader { proxy in
                ScrollView {
                    Text(op?.log.isEmpty == true ? "Running…" : (op?.log ?? ""))
                        .font(.system(size: 11, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .textSelection(.enabled)
                        .id("logBottom")
                }
                .onChange(of: op?.log) { _ in
                    proxy.scrollTo("logBottom", anchor: .bottom)
                }
            }
            .frame(minHeight: 220)
        }
    }
}

// MARK: - Empty state

struct EmptyState: View {
    let icon: String
    let title: String
    var detail: String = ""

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: icon)
        } description: {
            if !detail.isEmpty { Text(detail) }
        }
    }
}

// MARK: - Package row helpers

extension View {
    func rowMenu(_ menu: () -> some View) -> some View {
        self.contextMenu { menu() }
    }
}
