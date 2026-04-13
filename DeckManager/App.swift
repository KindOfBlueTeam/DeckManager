import SwiftUI

enum AppVersion {
    static let string = "2.0"
}

@main
struct DeckManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        FontManager.registerFonts()
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1100, height: 750)
        .defaultPosition(.center)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.async { [weak self] in
            for window in NSApp.windows {
                window.delegate = self
                if let hc = window.contentViewController {
                    WindowAppearance.apply(to: window, hostingController: hc)
                }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            for window in NSApp.windows {
                if let hc = window.contentViewController {
                    WindowAppearance.apply(to: window, hostingController: hc)
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: WindowAppearance.reapplyNotification,
            object: nil, queue: .main
        ) { _ in
            for window in NSApp.windows {
                if let hc = window.contentViewController {
                    WindowAppearance.apply(to: window, hostingController: hc)
                }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { NSApp.terminate(nil) }
        return true
    }
}
