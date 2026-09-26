import AppKit
@preconcurrency import ApplicationServices

/// The desktop-mischief toolbox: poop, sticky-note roasts, window nudges, Spotify revenge and the
/// wallpaper takeover. Everything is reversible or click-to-dismiss; no keystrokes, no file changes.
@MainActor
final class MischiefKit {
    private unowned let engine: PetEngine

    init(engine: PetEngine) {
        self.engine = engine
    }

    // MARK: Poop: 💩 windows around the pet. Only a click cleans each one up.

    private static let maxPoops = 40
    private var poops: [ClickAwayPanel] = []

    var poopCount: Int { poops.count }

    func dropPoop(count: Int) {
        let room = Self.maxPoops - poops.count
        guard room > 0 else { return }
        let petCenter = CGPoint(x: engine.position.x + PetWindow.size.width / 2, y: engine.position.y + 18)
        for _ in 0..<min(count, room) {
            let origin = CGPoint(x: petCenter.x + .random(in: -70...70), y: petCenter.y + .random(in: -10...40))
            let panel = ClickAwayPanel(size: CGSize(width: 46, height: 46), origin: origin)
            let label = NSTextField(labelWithString: "💩")
            label.font = .systemFont(ofSize: 34)
            label.alignment = .center
            label.frame = NSRect(x: 0, y: 4, width: 46, height: 40)
            panel.contentView?.addSubview(label)
            panel.onClick = { [weak self, weak panel] in
                guard let self, let panel else { return }
                self.poops.removeAll { $0 === panel }
                if self.poops.isEmpty { self.engine.say("You cleaned it all. I'll make more.", seconds: 4) }
            }
            poops.append(panel)
            panel.orderFrontRegardless()
        }
        if poops.count % 10 == 0 {
            engine.record("Poop report", "\(poops.count) 💩 on your screen. Click each one to clean it up.", show: false)
        }
    }

    func cleanAllPoop() {
        poops.forEach { $0.close() }
        poops.removeAll()
    }

    // MARK: Sticky notes: LLM roast of whatever app you're in instead of the pet

    private static let maxNotes = 8
    private var notes: [ClickAwayPanel] = []
    private static let cannedRoasts = [
        "I saw that tab.",
        "Oh, {app} again? Riveting.",
        "{app} won't love you back. I would. If you fed me.",
        "Still in {app}. I'm telling everyone.",
        "Touch grass. Or me. Preferably me.",
    ]

    func stickyNoteRoast() {
        let app = NSWorkspace.shared.frontmostApplication
        let appName = (app?.bundleIdentifier == Bundle.main.bundleIdentifier ? nil : app?.localizedName) ?? "your computer"
        let windowTitle = app.flatMap { Self.focusedWindowTitle(pid: $0.processIdentifier) } ?? ""
        let minutes = engine.minutesInFrontApp
        Task { [weak self] in
            let context = "They're in \(appName)" + (windowTitle.isEmpty ? "" : " (window: \"\(windowTitle.prefix(80))\")")
                + " and have been for about \(minutes) minute\(minutes == 1 ? "" : "s") instead of feeding you."
            let line = await PetEngine.requestLine(
                system: "You are a smug, passive-aggressive desktop pet leaving a sticky note for your owner. "
                    + "Write ONE short roast (under 18 words) about the app they're using. No quotes, no hashtags. Playful, not cruel.",
                user: context, maxTokens: 60)
                ?? Self.cannedRoasts.randomElement()!.replacingOccurrences(of: "{app}", with: appName)
            self?.showStickyNote(line)
        }
    }

    private func showStickyNote(_ text: String) {
        if notes.count >= Self.maxNotes { notes.removeFirst().close() }
        let size = CGSize(width: 210, height: 130)
        let frame = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let origin = CGPoint(x: .random(in: frame.minX + 20...max(frame.minX + 20, frame.maxX - size.width - 20)),
                             y: .random(in: frame.minY + 20...max(frame.minY + 20, frame.maxY - size.height - 20)))
        let panel = ClickAwayPanel(size: size, origin: origin)
        let bg = NSView(frame: NSRect(origin: .zero, size: size))
        bg.wantsLayer = true
        bg.layer?.backgroundColor = NSColor(calibratedRed: 1, green: 0.93, blue: 0.45, alpha: 1).cgColor
        bg.layer?.cornerRadius = 4
        bg.layer?.borderColor = NSColor.black.withAlphaComponent(0.15).cgColor
        bg.layer?.borderWidth = 1
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = NSFont(name: "Marker Felt", size: 15) ?? .systemFont(ofSize: 14)
        label.textColor = .black
        label.frame = NSRect(x: 12, y: 22, width: size.width - 24, height: size.height - 32)
        let sig = NSTextField(labelWithString: "— your pet 🐾  (click to dismiss)")
        sig.font = .systemFont(ofSize: 9)
        sig.textColor = .black.withAlphaComponent(0.5)
        sig.frame = NSRect(x: 12, y: 4, width: size.width - 24, height: 14)
        bg.addSubview(label)
        bg.addSubview(sig)
        panel.contentView?.addSubview(bg)
        panel.hasShadow = true
        panel.onClick = { [weak self, weak panel] in self?.notes.removeAll { $0 === panel } }
        notes.append(panel)
        panel.orderFrontRegardless()
        engine.record("Left a sticky note", text, show: false)
    }

    /// Title of an app's focused window via Accessibility (nil without permission).
    private static func focusedWindowTitle(pid: pid_t) -> String? {
        guard AXIsProcessTrusted() else { return nil }
        var win: CFTypeRef?, title: CFTypeRef?
        let app = AXUIElementCreateApplication(pid)
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &win) == .success,
              let win, AXUIElementCopyAttributeValue(win as! AXUIElement, kAXTitleAttribute as CFString, &title) == .success
        else { return nil }
        return title as? String
    }

    // MARK: Window nudge: slowly drags your frontmost window off-center (needs Accessibility)

    private var nudgeTimer: Timer?

    func nudgeFrontWindow() {
        guard nudgeTimer == nil else { return }
        guard AXIsProcessTrusted() else {
            engine.record("Window nudge failed", "Needs Accessibility: System Settings > Privacy & Security > Accessibility > ChaosTamagotchi.", show: false)
            return
        }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var winRef: CFTypeRef?, posRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &winRef) == .success,
              let winRef else { return }
        let win = winRef as! AXUIElement
        guard AXUIElementCopyAttributeValue(win, kAXPositionAttribute as CFString, &posRef) == .success,
              let posRef else { return }
        var start = CGPoint.zero
        AXValueGetValue(posRef as! AXValue, .cgPoint, &start)

        let angle = Double.random(in: 0..<(2 * .pi))
        let distance = CGFloat.random(in: 60...160)
        let delta = CGPoint(x: cos(angle) * distance, y: sin(angle) * distance)
        let steps = 60
        var i = 0
        engine.say("This window was in my spot.", seconds: 4)
        nudgeTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] t in
            MainActor.assumeIsolated {
                i += 1
                let k = CGFloat(i) / CGFloat(steps)
                var p = CGPoint(x: start.x + delta.x * k, y: max(25, start.y + delta.y * k))
                if let v = AXValueCreate(.cgPoint, &p) {
                    AXUIElementSetAttributeValue(win, kAXPositionAttribute as CFString, v)
                }
                if i >= steps {
                    t.invalidate()
                    self?.nudgeTimer = nil
                    self?.engine.record("Nudged your window", "\(app.localizedName ?? "Some app") moved \(Int(distance)) px. Deal with it.", show: false)
                }
            }
        }
    }

    // MARK: Spotify revenge: plays "All By Myself", then puts your music back

    nonisolated private static let revengeTrack = "spotify:track:0gsl92EMIScPGV1AU35nuD"  // Céline Dion, All By Myself
    nonisolated private static let revengeSeconds: UInt64 = 35

    func spotifyRevenge() {
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") != nil else {
            engine.record("Spotify revenge skipped", "Spotify isn't installed.", show: false)
            return
        }
        engine.say("Let me pick the music. 🎶", seconds: 5)
        Task.detached { [weak self] in
            // Remember what was playing so we can put it back.
            let wasRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").isEmpty
            let before = wasRunning ? PetEngine.osascript("""
                tell application "Spotify"
                  return (player state as text) & "|" & (id of current track) & "|" & (player position as text)
                end tell
                """).trimmingCharacters(in: .whitespacesAndNewlines) : ""
            let out = PetEngine.osascript("""
                tell application "Spotify"
                  play track "\(Self.revengeTrack)"
                  delay 1
                  return name of current track
                end tell
                """).trimmingCharacters(in: .whitespacesAndNewlines)
            await MainActor.run { [weak self] in
                self?.engine.record("Spotify revenge", out.isEmpty
                    ? "Couldn't control Spotify (allow Automation for Spotify in System Settings)."
                    : "Now playing: \(out). Your music comes back in \(Self.revengeSeconds)s.")
            }
            guard !out.isEmpty else { return }
            try? await Task.sleep(nanoseconds: Self.revengeSeconds * 1_000_000_000)
            let parts = before.components(separatedBy: "|")
            if parts.count == 3, parts[0] == "playing", parts[1] != Self.revengeTrack {
                let pos = Double(parts[2].replacingOccurrences(of: ",", with: ".")) ?? 0
                _ = PetEngine.osascript("""
                    tell application "Spotify"
                      play track "\(parts[1])"
                      delay 0.5
                      set player position to \(pos)
                    end tell
                    """)
            } else {
                _ = PetEngine.osascript("tell application \"Spotify\" to pause")
            }
            _ = self
        }
    }

    // MARK: Wallpaper takeover: sad pet portrait on every screen; feeding (or Restore) undoes it

    private static let wallpaperBackup = NSString(string: "~/.chaos_tamagotchi_wallpaper.txt").expandingTildeInPath

    func wallpaperTakeover() {
        let ws = NSWorkspace.shared
        guard let portrait = Self.renderSadPortrait() else { return }
        if !FileManager.default.fileExists(atPath: Self.wallpaperBackup) {  // keep the real originals only
            let lines = NSScreen.screens.compactMap { ws.desktopImageURL(for: $0)?.path }
            try? lines.joined(separator: "\n").write(toFile: Self.wallpaperBackup, atomically: true, encoding: .utf8)
        }
        for screen in NSScreen.screens {
            try? ws.setDesktopImageURL(portrait, for: screen, options: [.imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue])
        }
        engine.say("I redecorated. Do you like it? It's me. Sad.", seconds: 6)
        engine.record("Wallpaper takeover", "Your wallpaper is now a sad pet portrait. Feed the pet (or Restore Wallpaper) to get it back.")
    }

    func restoreWallpaper(announce: Bool = true) {
        guard let text = try? String(contentsOfFile: Self.wallpaperBackup, encoding: .utf8) else { return }
        let paths = text.split(separator: "\n").map(String.init)
        for (i, screen) in NSScreen.screens.enumerated() {
            guard let path = paths.indices.contains(i) ? paths[i] : paths.first else { continue }
            try? NSWorkspace.shared.setDesktopImageURL(URL(fileURLWithPath: path), for: screen, options: [:])
        }
        try? FileManager.default.removeItem(atPath: Self.wallpaperBackup)
        if announce { engine.say("Fine. Have your boring wallpaper back.") }
        engine.record("Wallpaper restored", "Back to your original wallpaper.", show: false)
    }

    /// Draws the pet, tinted blue and small in a huge empty room, with a sad caption. Unique file name
    /// each time because macOS caches wallpapers by path.
    private static func renderSadPortrait() -> URL? {
        let size = NSSize(width: 2560, height: 1600)
        let img = NSImage(size: size)
        img.lockFocus()
        NSGradient(starting: NSColor(calibratedRed: 0.05, green: 0.07, blue: 0.16, alpha: 1),
                   ending: NSColor(calibratedRed: 0.16, green: 0.2, blue: 0.35, alpha: 1))?.draw(in: NSRect(origin: .zero, size: size), angle: 90)
        if let url = Bundle.main.url(forResource: "mona-loading-default", withExtension: "gif"),
           let pet = NSImage(contentsOf: url) {
            let side: CGFloat = 520
            pet.draw(in: NSRect(x: (size.width - side) / 2, y: 520, width: side, height: side),
                     from: .zero, operation: .sourceOver, fraction: 0.85)
        }
        let tear = NSAttributedString(string: "💧", attributes: [.font: NSFont.systemFont(ofSize: 90)])
        tear.draw(at: NSPoint(x: size.width / 2 + 90, y: 820))
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        let caption = NSAttributedString(string: "you left me here.\nall by myself.", attributes: [
            .font: NSFont.systemFont(ofSize: 96, weight: .heavy), .foregroundColor: NSColor.white.withAlphaComponent(0.9),
            .paragraphStyle: para])
        caption.draw(in: NSRect(x: 0, y: 200, width: size.width, height: 260))
        img.unlockFocus()

        guard let tiff = img.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { return nil }
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ChaosTamagotchi", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))?
            .filter { $0.lastPathComponent.hasPrefix("sad_pet_") }.forEach { try? FileManager.default.removeItem(at: $0) }
        let file = dir.appendingPathComponent("sad_pet_\(Int(Date().timeIntervalSince1970)).png")
        return (try? png.write(to: file)) != nil ? file : nil
    }
}

/// Small borderless floating panel that closes itself when clicked (poop, sticky notes).
@MainActor
final class ClickAwayPanel: NSPanel {
    var onClick: (() -> Void)?

    init(size: CGSize, origin: CGPoint) {
        super.init(contentRect: NSRect(origin: origin, size: size), styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        contentView = NSView(frame: NSRect(origin: .zero, size: size))
    }

    override var canBecomeKey: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseUp {
            onClick?()
            close()
        } else {
            super.sendEvent(event)
        }
    }
}
