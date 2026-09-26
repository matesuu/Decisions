import AppKit

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var engine: PetEngine!
    private var petWindow: PetWindow!
    private var statusBar: StatusBarController!

    // No main nib, so NSApplicationMain wouldn't instantiate the delegate for us.
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)  // belt and braces with LSUIElement

        engine = PetEngine()
        petWindow = PetWindow(engine: engine)
        statusBar = StatusBarController(engine: engine)
        engine.attach(window: petWindow)
        petWindow.orderFrontRegardless()
        engine.start()
    }
}
