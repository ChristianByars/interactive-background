import SwiftUI

@main
struct InteractiveBackgroundApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Interactive Background", systemImage: "photo.on.rectangle") {
            Button("Quit") { NSApp.terminate(nil) }
        }
    }
}
