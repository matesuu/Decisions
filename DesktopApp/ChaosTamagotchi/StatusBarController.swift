import AppKit
import SwiftUI
import Combine

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let engine: PetEngine
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let infoItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let armedItem = NSMenuItem(title: "Chaos Armed", action: nil, keyEquivalent: "")
    private let mischiefMenu = NSMenu()
    private var rapSheetWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    init(engine: PetEngine) {
        self.engine = engine
        super.init()

        let menu = NSMenu()
        menu.delegate = self
        infoItem.isEnabled = false
        menu.addItem(infoItem)
        menu.addItem(.separator())

        let feed = NSMenuItem(title: "Feed / Check in", action: #selector(feed), keyEquivalent: "f")
        feed.target = self
        menu.addItem(feed)
        let sheet = NSMenuItem(title: "Rap Sheet", action: #selector(showRapSheetMenu), keyEquivalent: "r")
        sheet.target = self
        menu.addItem(sheet)
        armedItem.action = #selector(toggleArmed)
        armedItem.target = self
        menu.addItem(armedItem)
        menu.addItem(.separator())
        for (title, action) in [
            ("Text Mateo Now (commit crime)", #selector(crimeNow)),
            ("Hijack Cursor (3s)", #selector(hijack)),
            ("Grab a Desktop Folder", #selector(grabFolder)),
            ("Scatter Desktop Icons", #selector(scatter)),
            ("Drop Poop", #selector(poop)),
            ("Nudge Front Window", #selector(nudgeWindow)),
            ("Sticky Note Roast", #selector(stickyNote)),
            ("Spotify Revenge", #selector(spotify)),
            ("Wallpaper Takeover", #selector(wallpaper)),
        ] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            mischiefMenu.addItem(item)
        }
        let mischiefItem = NSMenuItem(title: "Do Mischief Now", action: nil, keyEquivalent: "")
        mischiefItem.submenu = mischiefMenu
        menu.addItem(mischiefItem)
        menu.addItem(.separator())
        for (title, action) in [
            ("Clean Up All Poop", #selector(cleanPoop)),
            ("Restore Wallpaper", #selector(restoreWallpaper)),
            ("Restore Desktop Icons", #selector(restoreIcons)),
        ] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu

        engine.showActivity = { [weak self] in self?.showRapSheet(activate: false) }

        engine.$mood
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.updateIcon($0) }
            .store(in: &cancellables)
        updateIcon(engine.mood)

        engine.$secondsLeft
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateTitle() }
            .store(in: &cancellables)
    }

    /// Menu bar readout: health % and countdown to the next mood tier.
    private func updateTitle() {
        let pct = Int((engine.health * 100).rounded())
        var text = " ♥ \(pct)%"
        if let next = engine.nextTier {
            let s = Int(next.seconds.rounded(.up))
            text += String(format: " · %@ in %d:%02d", next.name, s / 60, s % 60)
        }
        statusItem.button?.title = text
    }

    private func updateIcon(_ mood: Mood) {
        statusItem.button?.image = NSImage(systemSymbolName: mood.symbol, accessibilityDescription: "Chaos Tamagotchi")
    }

    func menuWillOpen(_ menu: NSMenu) {
        let mins = Int(ceil(max(0, engine.secondsLeft) / 60))
        let poop = engine.mischiefKit.poopCount
        infoItem.title = "Mood: \(engine.mood.rawValue) — \(mins) min left" + (poop > 0 ? " — 💩×\(poop)" : "")
        armedItem.state = PetEngine.isArmed ? .on : .off
    }

    @objc private func feed() { engine.checkIn() }

    @objc private func toggleArmed() {
        PetEngine.isArmed.toggle()
        armedItem.state = PetEngine.isArmed ? .on : .off
    }

    @objc private func hijack() { engine.hijackCursor() }
    @objc private func grabFolder() { engine.grabDesktopFolder() }
    @objc private func scatter() { engine.shuffleDesktopIcons() }
    @objc private func poop() { engine.mischiefKit.dropPoop(count: 3) }
    @objc private func nudgeWindow() {
        // Let the menu close and your previous app regain focus before we grab its window.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [engine] in engine.mischiefKit.nudgeFrontWindow() }
    }
    @objc private func stickyNote() { engine.mischiefKit.stickyNoteRoast() }
    @objc private func spotify() { engine.mischiefKit.spotifyRevenge() }
    @objc private func wallpaper() { engine.mischiefKit.wallpaperTakeover() }
    @objc private func cleanPoop() { engine.mischiefKit.cleanAllPoop() }
    @objc private func restoreWallpaper() { engine.mischiefKit.restoreWallpaper() }
    @objc private func restoreIcons() { engine.restoreDesktopIcons() }
    @objc private func crimeNow() { engine.commitCrime() }

    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func showRapSheetMenu() { showRapSheet(activate: true) }

    private func showRapSheet(activate: Bool) {
        if rapSheetWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 380),
                             styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            w.title = "Rap Sheet"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: RapSheetView(engine: engine))
            w.center()
            rapSheetWindow = w
        }
        // Pop the log window up (without stealing focus) so you can watch what the pet is doing.
        if activate { NSApp.activate(ignoringOtherApps: true) }
        rapSheetWindow?.orderFrontRegardless()
    }
}

struct RapSheetView: View {
    @ObservedObject var engine: PetEngine

    var body: some View {
        if engine.history.isEmpty {
            Text("No crimes yet. Keep ignoring the pet.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(engine.history) { entry in
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.label).font(.headline)
                    Text(entry.outcome).font(.callout).textSelection(.enabled)
                    Text(entry.date.formatted(date: .abbreviated, time: .standard))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 3)
            }
        }
    }
}
