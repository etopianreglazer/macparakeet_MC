import SplayCore
import SwiftUI

/// The app you never open. It exists to host the recording process, the
/// intents, and a findable-only Recents list. Everything visible happens in
/// the Dynamic Island (see the SplayWidgets target).
@main
struct SplayApp: App {
    @State private var boot = Boot()

    var body: some Scene {
        WindowGroup {
            RecentsView(boot: boot)
                .task { boot.run() }
        }
    }
}

@MainActor
@Observable
final class Boot {
    private(set) var environment: SplayEnvironment?
    private(set) var error: String?

    func run() {
        guard environment == nil, error == nil else { return }
        do {
            let env = try SplayEnvironment()
            environment = env
            RecordingCoordinator.shared.attach(env)
            env.warmUpSpeech()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Minimum viable Recents: the last transcripts, newest first, and where they
/// live. Reachable only if you go looking.
struct RecentsView: View {
    let boot: Boot
    @State private var rows: [Transcription] = []
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            List {
                if let error = boot.error ?? loadError {
                    Text(error).foregroundStyle(.red)
                }
                Section {
                    ForEach(rows, id: \.id) { row in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.fileName).font(.headline)
                            Text((row.cleanTranscript ?? row.rawTranscript ?? "").prefix(140))
                                .font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                        }
                        .contextMenu {
                            Button("Copy", systemImage: "doc.on.doc") {
                                UIPasteboard.general.string = row.cleanTranscript ?? row.rawTranscript ?? ""
                            }
                        }
                    }
                } header: {
                    Text("Recent")
                } footer: {
                    Text("Press the Action Button to record. Transcripts are in Files › Splay › MacParakeet-MC › Meetings.")
                }
            }
            .navigationTitle("Splay")
            .task(id: boot.environment == nil) { await load() }
            .refreshable { await load() }
        }
    }

    private func load() async {
        guard let env = boot.environment else { return }
        do {
            rows = try env.transcriptionRepo.fetchAll(limit: 50)
            loadError = nil
        } catch {
            loadError = "Could not read recent transcripts: \(error.localizedDescription)"
        }
    }
}
