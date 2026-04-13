import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Welcome screen — prompts user to load a collection JSON file.
struct WizardView: View {
    var onComplete: ((String) -> Void)?
    var onLoadPrevious: (() -> Void)?

    @State private var isDragging = false

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text("DeckManager")
                    .font(FontManager.philosopher(size: 16, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Text("v\(AppVersion.string)")
                    .font(FontManager.philosopher(size: 11))
                    .foregroundColor(.gray)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 24)

            Spacer()

            // Main content
            VStack(spacing: 20) {
                Image(systemName: "doc.badge.arrow.up")
                    .font(.system(size: 48, weight: .light))
                    .foregroundColor(.blue.opacity(0.7))

                Text("Load Your Collection")
                    .font(FontManager.philosopher(size: 22, weight: .bold))
                    .foregroundColor(.primary)

                Text("Import a Hearthstone collection JSON file to browse your cards and build decks.")
                    .font(FontManager.philosopher(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)

                // Drop zone
                VStack(spacing: 12) {
                    Button(action: { openFilePicker() }) {
                        HStack(spacing: 8) {
                            Image(systemName: "folder")
                                .font(FontManager.philosopher(size: 14))
                            Text("Choose JSON File")
                                .font(FontManager.philosopher(size: 15, weight: .semibold))
                        }
                        .frame(width: 220, height: 44)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)

                    Text("or drag and drop a .json file here")
                        .font(FontManager.philosopher(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(24)
                .frame(maxWidth: 340)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                        .foregroundColor(isDragging ? .blue : .secondary.opacity(0.3))
                )
                .onDrop(of: [.fileURL], isTargeted: $isDragging) { providers in
                    handleDrop(providers)
                }

                // Load previous collection
                if onLoadPrevious != nil {
                    Button(action: { onLoadPrevious?() }) {
                        Text("Use Last Collection")
                            .font(FontManager.philosopher(size: 13))
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            // Footer
            VStack(spacing: 4) {
                Text("Get your collection JSON from DeckRipper or deck.coach")
                    .font(FontManager.philosopher(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 16)
        }
        .frame(minWidth: 500, minHeight: 400)
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select your Hearthstone collection JSON file"

        if panel.runModal() == .OK, let url = panel.url {
            loadCollection(from: url)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            DispatchQueue.main.async {
                loadCollection(from: url)
            }
        }
        return true
    }

    private func loadCollection(from url: URL) {
        // Copy to our expected temp location so the rest of the app can find it
        let destPath = NSTemporaryDirectory() + "hearthstone_collection.json"
        try? FileManager.default.removeItem(atPath: destPath)
        try? FileManager.default.copyItem(at: url, to: URL(fileURLWithPath: destPath))
        onComplete?(destPath)
    }
}
