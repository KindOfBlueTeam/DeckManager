import AppKit
import SwiftUI

/// Shared window appearance logic applied to all DeckManager windows.
enum WindowAppearance {

    static let reapplyNotification = Notification.Name("com.deckripper.reapplyBackground")

    /// Apply the current color scheme to a window.
    static func apply(to window: NSWindow, hostingController: NSViewController) {
        let store = UserDataStore.shared

        // Color scheme
        switch store.appearanceMode {
        case "dark":  window.appearance = NSAppearance(named: .darkAqua)
        case "light": window.appearance = NSAppearance(named: .aqua)
        default:      window.appearance = nil
        }

        // Ensure the hosting controller is set
        if window.contentViewController !== hostingController {
            window.contentViewController = hostingController
        }
    }
}
