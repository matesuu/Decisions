import AppKit
import SwiftUI
import Combine

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let engine: PetEngine
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let infoItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let armedItem = NSMenuItem(title: "Chaos Armed", action: nil, keyEquivalent: "")
    private let safeItem = NSMenuItem(title: "Safe Mode (just cute)", action: nil, keyEquivalent: "")
    private let mischiefMenu = NSMenu()
    private var cancellables = Set<AnyCancellable>()

    init(engine: PetEngine) {
        self.engine = engine
        super.init()

        let menu = NSMenu()
        menu.delegate = self
        infoItem.isEnabled = false
        menu.addItem(infoItem)
        menu.addItem(.separator())

        let feed = NSMenuItem(title: "Feed (+15%)", action: #selector(feed), keyEquivalent: "f")
        feed.target = self
        menu.addItem(feed)
        armedItem.action = #selector(toggleArmed)
        armedItem.target = self
        menu.addItem(armedItem)
        safeItem.action = #selector(toggleSafe)
        safeItem.target = self
        menu.addItem(safeItem)
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
            ("Play Mommy ASMR", #selector(asmr)),
            ("Random Google Images", #selector(images)),
        ] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            mischiefMenu.addItem(item)
        }
        let mischiefItem = NSMenuItem(title: "Do Mischief Now", action: nil, keyEquivalent: "")
        mischiefItem.submenu = mischiefMenu
        menu.addItem(mischiefItem)
        menu.addItem(.separator())
        let restore = NSMenuItem(title: "Restore Everything", action: #selector(restoreAll), keyEquivalent: "r")
        restore.target = self
        menu.addItem(restore)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu

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
        safeItem.state = PetEngine.isSafeMode ? .on : .off
    }

    @objc private func toggleSafe() {
        engine.setSafeMode(!PetEngine.isSafeMode)
        safeItem.state = PetEngine.isSafeMode ? .on : .off
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
    @objc private func asmr() { engine.mischiefKit.openMommyASMR() }
    @objc private func images() { engine.mischiefKit.openRandomImages() }
    @objc private func restoreAll() { engine.restoreEverything() }
    @objc private func crimeNow() { engine.commitCrime() }

    @objc private func quit() { NSApp.terminate(nil) }
}
