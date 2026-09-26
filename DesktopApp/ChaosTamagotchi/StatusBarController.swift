import AppKit
import SwiftUI
import Combine

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let engine: PetEngine
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let infoItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let armedItem = NSMenuItem(title: "Chaos Armed", action: nil, keyEquivalent: "")
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
        let sheet = NSMenuItem(title: "Rap Sheet", action: #selector(showRapSheet), keyEquivalent: "r")
        sheet.target = self
        menu.addItem(sheet)
        armedItem.action = #selector(toggleArmed)
        armedItem.target = self
        menu.addItem(armedItem)
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
    }

    private func updateIcon(_ mood: Mood) {
        statusItem.button?.image = NSImage(systemSymbolName: mood.symbol, accessibilityDescription: "Chaos Tamagotchi")
    }

    func menuWillOpen(_ menu: NSMenu) {
        let mins = Int(ceil(max(0, engine.secondsLeft) / 60))
        infoItem.title = "Mood: \(engine.mood.rawValue) — \(mins) min left"
        armedItem.state = PetEngine.isArmed ? .on : .off
    }

    @objc private func feed() { engine.checkIn() }

    @objc private func toggleArmed() {
        PetEngine.isArmed.toggle()
        armedItem.state = PetEngine.isArmed ? .on : .off
    }

    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func showRapSheet() {
        if rapSheetWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 380),
                             styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            w.title = "Rap Sheet"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: RapSheetView(engine: engine))
            w.center()
            rapSheetWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        rapSheetWindow?.makeKeyAndOrderFront(nil)
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
