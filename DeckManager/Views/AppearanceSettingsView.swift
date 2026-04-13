import SwiftUI

/// Popover for settings: player name, color scheme, and collection management.
struct AppearanceSettingsView: View {
    @ObservedObject private var userStore = UserDataStore.shared
    @State private var editingName: String = ""
    var onReloadCollection: (() -> Void)?

    var body: some View {
        Form {
            Section("Player Name") {
                HStack {
                    TextField("Enter your name...", text: $editingName)
                        .textFieldStyle(.roundedBorder)
                        .onAppear { editingName = userStore.playerName ?? "" }
                        .onSubmit { userStore.setPlayerName(editingName.isEmpty ? nil : editingName) }
                    Button("Save") {
                        userStore.setPlayerName(editingName.isEmpty ? nil : editingName)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }

            Section("Color Scheme") {
                Picker("Appearance", selection: $userStore.appearanceMode) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.radioGroup)
                .onChange(of: userStore.appearanceMode) { _ in
                    userStore.saveAppearance()
                }
            }

            if let reload = onReloadCollection {
                Section("Collection") {
                    Button(action: reload) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Load Different Collection")
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 300, height: onReloadCollection != nil ? 280 : 220)
    }
}
