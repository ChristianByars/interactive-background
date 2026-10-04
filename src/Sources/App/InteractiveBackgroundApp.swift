import SwiftUI

@main
struct InteractiveBackgroundApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Interactive Background", systemImage: "photo.on.rectangle") {
            MenuContent(model: appDelegate.model)
        }

        Window("Library", id: "library") {
            LibraryView(model: appDelegate.model)
        }
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
    }
}
