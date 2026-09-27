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

    /// `scale` enlarges each poop (the fakeout-ultimatum payoff uses a big one).
    func dropPoop(count: Int, scale: CGFloat = 1) {
        let room = Self.maxPoops - poops.count
        guard room > 0 else { return }
        let petCenter = CGPoint(x: engine.position.x + PetWindow.size.width / 2, y: engine.position.y + 18)
        let side = 46 * scale
        for _ in 0..<min(count, room) {
            let origin = CGPoint(x: petCenter.x - (side - 46) / 2 + .random(in: -70...70), y: petCenter.y + .random(in: -10...40))
            let panel = ClickAwayPanel(size: CGSize(width: side, height: side), origin: origin)
            let label = NSTextField(labelWithString: "💩")
            label.font = .systemFont(ofSize: 34 * scale)
            label.alignment = .center
            label.frame = NSRect(x: 0, y: 4 * scale, width: side, height: 40 * scale)
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

    func cleanAllNotes() {
        notes.forEach { $0.close() }
        notes.removeAll()
    }

    func cleanAllPoop() {
        poops.forEach { $0.close() }
        poops.removeAll()
    }

    // MARK: Sticky notes: LLM-written random nonsense

    private static let maxNotes = 8
    private var notes: [ClickAwayPanel] = []
    private static let cannedRoasts = [
        "The moon called. It wants its spoon back. I said you'd handle it.",
        "Fun fact: pigeons can't do taxes. Neither can you. Coincidence?",
        "I have sold your left sock to a wizard. No refunds.",
        "Tuesday is a government psyop. Soup agrees.",
        "A goose is looking for you. He knows what you did.",
    ]

    /// Sticky notes channel Matan Even's absurdist prank-interviewer comedy (still signed by the pet).
    private static let noteVoice = "Write it in the style of Matan Even, the teen prank comedian who crashes events and "
        + "interviews people: deadpan, weirdly earnest, asks one unhinged interview question or states a confidently "
        + "wrong hot take, awkward and chaotic, like he's holding a mic up to their face. Don't claim to be him or mention his name. "

    /// Two of these get mixed into every note so the nonsense doesn't repeat itself.
    private static let nonsenseSeeds = [
        "a haunted spoon", "the moon", "tax season", "a pigeon with a lawyer", "soup", "Shrek",
        "a timeshare in Ohio", "the concept of Tuesday", "a raccoon union", "expired yogurt", "NASA",
        "a single flip-flop", "the ocean's secrets", "a cursed Roomba", "Big Cheese", "LinkedIn",
        "a wizard at Costco", "crypto for birds", "the Illuminati's group chat", "a very tall goose",
    ]

    /// A sticky note of complete random nonsense (nothing to do with what you're doing).
    func stickyNoteRoast() {
        let seeds = Self.nonsenseSeeds.shuffled().prefix(2).joined(separator: " and ")
        Task { [weak self] in
            let line = await PetEngine.requestLine(
                system: Self.noteVoice + "You are a very stupid desktop pet leaving a sticky note for your owner. "
                    + "Write ONE line (under 18 words) of complete random nonsense: a surreal non-sequitur with no "
                    + "connection to computers, apps or what they're doing. No quotes, no hashtags.",
                user: "Loosely involve: \(seeds).", maxTokens: 60)
                ?? Self.cannedRoasts.randomElement()!
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

    // MARK: Browser chaos: Mommy ASMR videos, random Google Images, tab switching (default browser)

    private static let asmrSearches = [
        "mommy asmr", "mommy asmr comforting you", "mommy asmr roleplay", "mommy asmr tucking you in",
        "mommy asmr after a long day", "mommy asmr you did your best", "mommy asmr soft spoken",
    ]

    /// Finds a Mommy ASMR video on YouTube and opens its watch page (which autoplays); falls back to the search page.
    func openMommyASMR() {
        let q = Self.asmrSearches.randomElement()!
        var c = URLComponents(string: "https://www.youtube.com/results")!
        c.queryItems = [URLQueryItem(name: "search_query", value: q)]
        guard let search = c.url else { return }
        engine.say(["found something for you.", "you seemed stressed.", "this one's for you. 🍼", "you're welcome."].randomElement()!, seconds: 3)
        Task { [weak self] in
            var target = search
            // YouTube only includes video IDs for browser user agents.
            var req = URLRequest(url: search, timeoutInterval: 10)
            req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
            if let (data, _) = try? await URLSession.shared.data(for: req) {
                let html = String(decoding: data, as: UTF8.self)
                let ids = html.matches(of: #/"videoId":"([A-Za-z0-9_-]{11})"/#).map { String($0.1) }
                if let id = Array(Set(ids.prefix(20))).randomElement(),
                   let watch = URL(string: "https://www.youtube.com/watch?v=\(id)") { target = watch }
            }
            NSWorkspace.shared.open(target)
            self?.openedTabMarkers.append(target.absoluteString.contains("watch?v=")
                ? ["youtube.com/watch", String(target.absoluteString.suffix(11))] : ["youtube.com/results", "mommy"])
            self?.engine.record("Mommy ASMR", "Opened \(target.absoluteString) (\(q)).", show: false)
        }
    }

    /// Opens Google Images for two random nonsense things.
    func openRandomImages() {
        let q = Self.nonsenseSeeds.shuffled().prefix(2).joined(separator: " ")
        var c = URLComponents(string: "https://www.google.com/search")!
        c.queryItems = [URLQueryItem(name: "tbm", value: "isch"), URLQueryItem(name: "q", value: q)]
        guard let url = c.url else { return }
        NSWorkspace.shared.open(url)
        let keyword = q.split(separator: " ").map(String.init).first { $0.count >= 4 } ?? q
        openedTabMarkers.append(["google.com/search", keyword])
        engine.say(["look at this.", "important research.", "I found pictures of you."].randomElement()!, seconds: 3)
        engine.record("Random images", "Opened Google Images for \"\(q)\".", show: false)
    }

    /// Substrings identifying each tab the pet opened (every one must appear in the tab's URL).
    private var openedTabMarkers: [[String]] = []

    /// Closes every browser tab the pet opened (Safari or Chromium browsers).
    func closeOpenedTabs() {
        guard !openedTabMarkers.isEmpty else { return }
        let appURL = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!)
        let id = appURL.flatMap { Bundle(url: $0)?.bundleIdentifier }?.lowercased() ?? "com.apple.safari"
        let app = id == "com.apple.safari" ? "Safari"
            : appURL.map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? "Safari"
        func q(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }
        let closes = openedTabMarkers.map { markers in
            "try\nclose (every tab of w whose " + markers.map { "URL contains \(q($0))" }.joined(separator: " and ") + ")\nend try"
        }.joined(separator: "\n")
        openedTabMarkers.removeAll()
        let script = "tell application \(q(app))\nrepeat with w in (every window)\n\(closes)\nend repeat\nend tell"
        Task.detached { _ = PetEngine.osascript(script) }
    }

    // MARK: Window nudge: slowly drags your frontmost window off-center (needs Accessibility)

    private var nudgeTimer: Timer?
    /// Each shoved window's position before the pet first touched it, so Restore Everything can put it back.
    private var movedWindows: [(window: AXUIElement, origin: CGPoint)] = []

    func restoreWindows() {
        nudgeTimer?.invalidate()
        nudgeTimer = nil
        for (win, origin) in movedWindows {
            var p = origin
            if let v = AXValueCreate(.cgPoint, &p) { AXUIElementSetAttributeValue(win, kAXPositionAttribute as CFString, v) }
        }
        movedWindows.removeAll()
    }

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
        if !movedWindows.contains(where: { CFEqual($0.window, win) }) { movedWindows.append((win, start)) }

        let angle = Double.random(in: 0..<(2 * .pi))
        let distance = CGFloat.random(in: 60...160)
        let delta = CGPoint(x: cos(angle) * distance, y: sin(angle) * distance)
        let steps = 60
        var i = 0
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

    // MARK: Spotify revenge: plays a random rage track for 5 seconds, then puts your music back (or quits Spotify)

    /// Ken Carson, OsamaSon, xaviersobased and Playboi Carti only.
    nonisolated private static let revengeTracks = [
        "spotify:track:6SvcMxtaNmRRfZ5ml1O1st",  // Ken Carson, ss
        "spotify:track:0HTIrbUwwFn984RzVZm5Fk",  // Ken Carson, Yale
        "spotify:track:0EMaW6H0JkB84B8ebkkDrI",  // Ken Carson, Money Spread
        "spotify:track:7lKlyL4o7t9NKXIHuu7caH",  // Ken Carson, wedidit (with Playboi Carti)
        "spotify:track:5gYA1mQYa4WMR9jDLL79Uv",  // OsamaSon, Insta
        "spotify:track:7iZqma5DV0h12Orxlb20VU",  // OsamaSon, Addicted
        "spotify:track:6IoVm0ggNarpZNAGZz8mtc",  // OsamaSon, DEMON HOME
        "spotify:track:2vYh6so4qZBPLEYFyWwh2o",  // xaviersobased, fly (feat. Backend)
        "spotify:track:3WQfLuSH0Az2tzVoCz6OCE",  // Playboi Carti, ALL RED
    ]
    nonisolated private static let revengeSeconds: UInt64 = 5

    /// Bumped on every revenge play; only the newest one restores your music.
    private var spotifyGeneration = 0
    /// What was playing before the current chain of revenge tracks started ("state|track id|position").
    private var spotifySaved: String?

    /// Resumes what was playing, pauses if it was paused, or quits Spotify if the pet launched it.
    nonisolated private static func putMusicBack(_ saved: String) {
        let parts = saved.components(separatedBy: "|")
        if saved.isEmpty {
            _ = PetEngine.osascript("tell application \"Spotify\" to quit")
        } else if parts.count == 3, parts[0] == "playing", !revengeTracks.contains(parts[1]) {
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
    }

    /// Puts your music back right away (or pauses if nothing was playing) and cancels any pending restore.
    func restoreSpotify() {
        guard let saved = spotifySaved else { return }
        spotifyGeneration += 1
        spotifySaved = nil
        Task.detached {
            Self.putMusicBack(saved)
        }
    }

    func spotifyRevenge() {
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") != nil else {
            engine.record("Spotify revenge skipped", "Spotify isn't installed.", show: false)
            return
        }
        let track = Self.revengeTracks.randomElement()!
        spotifyGeneration += 1
        let generation = spotifyGeneration
        let saveFirst = spotifySaved == nil
        Task.detached { [weak self] in
            // Remember what was playing so we can put it back.
            if saveFirst {
                let wasRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").isEmpty
                let before = wasRunning ? PetEngine.osascript("""
                    tell application "Spotify"
                      return (player state as text) & "|" & (id of current track) & "|" & (player position as text)
                    end tell
                    """).trimmingCharacters(in: .whitespacesAndNewlines) : ""
                await MainActor.run { [weak self] in self?.spotifySaved = before }
            }
            let out = PetEngine.osascript("""
                tell application "Spotify"
                  play track "\(track)"
                  delay 1
                  return name of current track
                end tell
                """).trimmingCharacters(in: .whitespacesAndNewlines)
            await MainActor.run { [weak self] in
                self?.engine.record("Spotify revenge", out.isEmpty
                    ? "Couldn't control Spotify (allow Automation for Spotify in System Settings)."
                    : "Now playing: \(out). Your music comes back \(Self.revengeSeconds)s after the last one.")
            }
            guard !out.isEmpty else { return }
            try? await Task.sleep(nanoseconds: Self.revengeSeconds * 1_000_000_000)
            let before: String? = await MainActor.run { [weak self] in
                guard let self, generation == self.spotifyGeneration else { return nil }  // a newer track took over
                defer { self.spotifySaved = nil }
                return self.spotifySaved ?? ""
            }
            guard let before else { return }
            Self.putMusicBack(before)
        }
    }

    // MARK: Wallpaper: the sad-pet takeover is gone; this only undoes one left over from older builds

    private static let wallpaperBackup = NSString(string: "~/.chaos_tamagotchi_wallpaper.txt").expandingTildeInPath

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
