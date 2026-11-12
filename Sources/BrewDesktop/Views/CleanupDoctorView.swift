import SwiftUI

struct CleanupView: View {
    @EnvironmentObject var store: BrewStore
    @State private var confirmCleanup = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                if !store.cleanupReport.freeSpace.isEmpty {
                    Text("Can free ~\(store.cleanupReport.freeSpace)")
                        .font(.subheadline.weight(.medium))
                }
                Text("\(store.cleanupReport.items.count) items")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Analyze") { store.analyzeCleanup() }
                Button {
                    confirmCleanup = true
                } label: {
                    Label("Run Cleanup", systemImage: "trash")
                }
                .disabled(store.cleanupReport.items.isEmpty)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .confirmationDialog(
                "Run brew cleanup?",
                isPresented: $confirmCleanup,
                titleVisibility: .visible
            ) {
                Button("Run Cleanup", role: .destructive) { store.runCleanup() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Deletes old versions and stale files listed in the analysis above. Cannot be undone.")
            }
            Divider()

            if store.cleanupReport.items.isEmpty {
                EmptyState(icon: "trash", title: "Nothing to clean",
                           detail: "Run Analyze to check for old versions and stale files.")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(store.cleanupReport.items, id: \.self) { line in
                            Text(line)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .task { if store.cleanupReport.items.isEmpty { store.analyzeCleanup() } }
    }
}

struct DoctorView: View {
    @EnvironmentObject var store: BrewStore

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                if let ok = store.doctorOK {
                    Badge(ok ? "no problems found" : "problems detected", color: ok ? .green : .red)
                }
                Spacer()
                Button {
                    store.runDoctor()
                } label: {
                    Label("Run brew doctor", systemImage: "cross.case")
                }
                .disabled(store.currentOp?.running == true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            Divider()

            if store.doctorText.isEmpty {
                EmptyState(icon: "cross.case", title: "Doctor not run yet",
                           detail: "brew doctor checks your setup for common problems.")
            } else {
                ScrollView {
                    Text(store.doctorText)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .textSelection(.enabled)
                }
            }
        }
    }
}
