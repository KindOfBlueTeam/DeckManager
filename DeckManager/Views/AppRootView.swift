import SwiftUI

/// Root view — shows JSON import wizard or collection browser.
struct AppRootView: View {
    @State private var collectionPath: String?
    @State private var showingWizard = true
    @ObservedObject private var userStore = UserDataStore.shared

    private var colorScheme: ColorScheme? {
        switch userStore.appearanceMode {
        case "dark": return .dark
        case "light": return .light
        default: return nil
        }
    }

    var body: some View {
        ZStack {
            if let path = collectionPath, !showingWizard {
                CollectionView(collectionPath: path, onReloadCollection: {
                    withAnimation { showingWizard = true }
                })
                .transition(.opacity)
            } else {
                Color(nsColor: .windowBackgroundColor)
                    .ignoresSafeArea()

                VStack {
                    Spacer()
                    WizardView(
                        onComplete: { path in
                            collectionPath = path
                            withAnimation(.easeInOut(duration: 0.3)) {
                                showingWizard = false
                            }
                        },
                        onLoadPrevious: hasPreviousCollection ? {
                            loadPreviousCollection()
                        } : nil
                    )
                    Spacer()
                }
            }
        }
        .frame(minWidth: 620, minHeight: 320)
        .preferredColorScheme(colorScheme)
    }

    private var previousCollectionPath: String {
        NSTemporaryDirectory() + "hearthstone_collection.json"
    }

    private var hasPreviousCollection: Bool {
        FileManager.default.fileExists(atPath: previousCollectionPath)
    }

    private func loadPreviousCollection() {
        collectionPath = previousCollectionPath
        withAnimation(.easeInOut(duration: 0.3)) {
            showingWizard = false
        }
    }
}
