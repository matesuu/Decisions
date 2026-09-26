import AppKit
import Combine
import CoreGraphics

// MARK: - Easy-to-edit configuration

/// GUI apps get a minimal PATH; add the usual places python3 (with deps) lives.
let sidecarExtraPath = "/opt/homebrew/bin:/usr/local/bin:/opt/anaconda3/bin"

/// Default deadline: 5 minutes. Mischief cadence below is tuned for 30 min and scaled down proportionally.
let defaultDeadlineSeconds: TimeInterval = 300

/// Secrets live outside the repo: KEY=VALUE lines in ~/.chaos_tamagotchi.env (real env vars win).
let appEnvironment: [String: String] = {
    var env: [String: String] = [:]
    let path = NSString(string: "~/.chaos_tamagotchi.env").expandingTildeInPath
    if let text = try? String(contentsOfFile: path, encoding: .utf8) {
        for line in text.split(whereSeparator: \.isNewline) {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard !t.hasPrefix("#"), let eq = t.firstIndex(of: "=") else { continue }
            env[String(t[..<eq])] = String(t[t.index(after: eq)...]).trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
        }
    }
    return env.merging(ProcessInfo.processInfo.environment) { _, real in real }
}()

/// The Python sidecar is copied into the app bundle at build time. Set CHAOS_SIDECAR_PATH
/// (env or ~/.chaos_tamagotchi.env) to run a different copy, e.g. while editing it.
let sidecarScriptPath: String = appEnvironment["CHAOS_SIDECAR_PATH"]
    ?? Bundle.main.path(forResource: "chaos_action", ofType: "py")
    ?? "chaos_action.py"

// MARK: - Model types

enum Mood: String {
    case content, restless, anxious, feral, committingCrimes

    var symbol: String {
        switch self {
        case .content: return "pawprint.fill"
        case .restless: return "pawprint"
        case .anxious: return "exclamationmark.triangle"
        case .feral: return "flame.fill"
        case .committingCrimes: return "bolt.trianglebadge.exclamationmark.fill"
        }
    }
    /// Seconds between mischief events; nil = none.
    var mischiefInterval: TimeInterval? {
        switch self {
        case .content: return 45
        case .restless: return 90
        case .anxious: return 60
        case .feral: return 30
        case .committingCrimes: return 20
        }
    }

    static func from(fraction f: Double) -> Mood {
        switch f {
        case ..<0.25: return .content
        case ..<0.5: return .restless
        case ..<0.75: return .anxious
        case ..<1.0: return .feral
        default: return .committingCrimes
        }
    }
}

struct ChaosLogEntry: Identifiable {
    let id = UUID()
    let date: Date
    let label: String
    let outcome: String
}

// MARK: - Engine

@MainActor
final class PetEngine: ObservableObject {
    @Published private(set) var mood: Mood = .content
    @Published private(set) var secondsLeft: TimeInterval
    @Published var position: CGPoint = .zero
    @Published private(set) var speechText: String?
    @Published private(set) var history: [ChaosLogEntry] = []
    @Published private(set) var facingRight = false

    /// Debug-only override: set CHAOS_DEBUG_DEADLINE_SECONDS (e.g. 30) in the Xcode scheme
    /// to fast-forward through all moods. Never set in normal use.
    let deadlineSeconds: TimeInterval
    private var elapsed: TimeInterval = 0
    private var triggeredThisCycle = false
    private var sinceMischief: TimeInterval = 0
    private var direction: CGFloat = -1
    private var directionTimeLeft: TimeInterval = 5
    private var speechTask: Task<Void, Never>?
    private var tickTimer: Timer?
    private var walkTimer: Timer?
    private weak var window: PetWindow?

    /// UserDefaults-backed "Chaos Armed" switch. Default ON (texts are still pinned to the test contact).
    static var isArmed: Bool {
        get { UserDefaults.standard.bool(forKey: "chaosArmed") }
        set { UserDefaults.standard.set(newValue, forKey: "chaosArmed") }
    }

    init() {
        UserDefaults.standard.register(defaults: ["chaosArmed": true])  // armed by default (toggle in menu)
        let override = appEnvironment["CHAOS_DEBUG_DEADLINE_SECONDS"].flatMap(Double.init)
        deadlineSeconds = override ?? defaultDeadlineSeconds
        secondsLeft = deadlineSeconds
    }

    func attach(window: PetWindow) {
        self.window = window
        position = window.frame.origin
    }

    func start() {
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        walkTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.walk(dt: 1.0 / 30) }
        }
    }

    /// 0...1 fraction of time remaining.
    var health: Double { max(0, min(1, secondsLeft / deadlineSeconds)) }

    /// Seconds until the next mood tier, and its name (nil once committingCrimes).
    var nextTier: (name: String, seconds: TimeInterval)? {
        let elapsed = deadlineSeconds - secondsLeft
        for (f, name) in [(0.25, "restless"), (0.5, "anxious"), (0.75, "feral"), (1.0, "crimes")] where elapsed < deadlineSeconds * f {
            return (name, deadlineSeconds * f - elapsed)
        }
        return nil
    }

    // MARK: Check-in

    func checkIn() {
        NSLog("ChaosTamagotchi check-in (was %@s left)", String(Int(secondsLeft)))
        elapsed = 0
        secondsLeft = deadlineSeconds
        triggeredThisCycle = false
        sinceMischief = 0
        mood = .content
        didSpotifyThisCycle = false
        didWallpaperThisCycle = false
        mischiefKit.restoreWallpaper(announce: false)  // feeding earns your wallpaper back; poop stays
        say("Nom. Fine. You're forgiven. For now.")
    }

    // MARK: Tick (1 Hz)

    /// How long you've stayed in the current frontmost app (fuel for sticky-note roasts).
    private var frontAppID: String?
    private var frontAppSeconds = 0
    var minutesInFrontApp: Int { frontAppSeconds / 60 }

    private func tick() {
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if front != Bundle.main.bundleIdentifier {
            if front != frontAppID { frontAppID = front; frontAppSeconds = 0 } else { frontAppSeconds += 1 }
        }
        elapsed += 1
        secondsLeft = max(0, deadlineSeconds - elapsed)
        let newMood = Mood.from(fraction: elapsed / deadlineSeconds)
        if newMood != mood { mood = newMood }

        // Scale mischief cadence down when the deadline is shortened for debugging.
        let scale = min(1, deadlineSeconds / 1800)
        sinceMischief += 1
        let due = mood == .content ? 45 : max(3, (mood.mischiefInterval ?? 0) * scale)  // baseline 45s is never scaled
        if mood.mischiefInterval != nil, sinceMischief >= due {
            sinceMischief = 0
            mischief()
        }

        if mood == .committingCrimes && !triggeredThisCycle {
            triggeredThisCycle = true
            commitCrime()
        }
    }

    // MARK: Roaming (30 Hz): wander to random spots anywhere on the screen

    private var target: CGPoint?

    private func walk(dt: TimeInterval) {
        guard let window else { return }
        let screen = (window.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        let maxX = screen.maxX - PetWindow.size.width, maxY = screen.maxY - PetWindow.size.height
        let speed: CGFloat = switch mood {
        case .content: 30
        case .restless: 55
        case .anxious: 90
        case .feral, .committingCrimes: 150
        }
        directionTimeLeft -= dt
        if target == nil || directionTimeLeft <= 0 {
            // Half the time hang out along the bottom edge, otherwise roam anywhere.
            let y = Bool.random() ? screen.minY : .random(in: screen.minY...max(screen.minY, maxY))
            target = CGPoint(x: .random(in: screen.minX...max(screen.minX, maxX)), y: y)
            directionTimeLeft = .random(in: 4...10)
        }
        guard let t = target else { return }
        var p = position
        let dx = t.x - p.x, dy = t.y - p.y
        let dist = hypot(dx, dy)
        if dist < 4 {
            target = nil
            directionTimeLeft = 0
            return
        }
        let step = min(dist, speed * dt)
        p.x += dx / dist * step
        p.y += dy / dist * step
        p.x = min(max(p.x, screen.minX), max(screen.minX, maxX))
        p.y = min(max(p.y, screen.minY), max(screen.minY, maxY))
        if abs(dx) > 2 { facingRight = dx > 0 }
        position = p
        window.setFrameOrigin(p)
    }

    // MARK: Mischief (never synthesizes keystrokes into other apps)

    /// Per-cycle one-shots so the heavy stunts don't repeat every few seconds.
    private var didSpotifyThisCycle = false
    private var didWallpaperThisCycle = false
    private(set) lazy var mischiefKit = MischiefKit(engine: self)

    private func mischief() {
        let kit = mischiefKit
        switch mood {
        case .content:
            if Int.random(in: 0..<3) == 0 { kit.dropPoop(count: 1) }
            if Int.random(in: 0..<4) == 0 { after(4) { self.hijackCursor() } }
        case .restless:
            nudgeCursor()
            kit.dropPoop(count: 1)
            if Bool.random() { kit.stickyNoteRoast() }
        case .anxious:
            nudgeCursor()
            kit.dropPoop(count: 2)
            if Bool.random() { kit.nudgeFrontWindow() } else { kit.stickyNoteRoast() }
        case .feral, .committingCrimes:
            nudgeCursor()
            kit.dropPoop(count: 3)
            var stunts: [() -> Void] = [
                { self.grabDesktopFolder() }, { self.hijackCursor() },
                { kit.nudgeFrontWindow() }, { kit.stickyNoteRoast() },
            ]
            if !didSpotifyThisCycle { stunts.append { self.didSpotifyThisCycle = true; kit.spotifyRevenge() } }
            if !didWallpaperThisCycle { stunts.append { self.didWallpaperThisCycle = true; kit.wallpaperTakeover() } }
            stunts.randomElement()!()
        }
    }

    private func after(_ seconds: TimeInterval, _ block: @escaping @MainActor () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { MainActor.assumeIsolated { block() } }
    }

    /// Records an activity in the Rap Sheet and pops the app window open so you can watch.
    func record(_ label: String, _ outcome: String, show: Bool = true) {
        history.insert(ChaosLogEntry(date: Date(), label: label, outcome: outcome), at: 0)
        if history.count > 100 { history.removeLast(history.count - 100) }
        if show { showActivity?() }
    }

    /// Set by the status bar controller: brings the Rap Sheet window forward.
    var showActivity: (() -> Void)?

    // MARK: Cursor hijack: grabs the pointer and yanks it around for ~3s (no keystrokes, no clicks)

    private var hijackTimer: Timer?

    func hijackCursor() {
        guard hijackTimer == nil, let start = CGEvent(source: nil)?.location else { return }
        let bounds = CGDisplayBounds(CGMainDisplayID())
        var pos = start
        var dest = randomPoint(in: bounds)
        var ticks = 0
        say("MINE. MINE. MINE.", seconds: 3)
        hijackTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] t in
            MainActor.assumeIsolated {
                ticks += 1
                let dx = dest.x - pos.x, dy = dest.y - pos.y
                let d = hypot(dx, dy)
                if d < 30 { dest = self?.randomPoint(in: bounds) ?? dest }
                let step: CGFloat = 45  // px per frame, fast enough to be infuriating
                pos.x += dx / max(d, 1) * step + .random(in: -6...6)
                pos.y += dy / max(d, 1) * step + .random(in: -6...6)
                CGWarpMouseCursorPosition(pos)
                CGAssociateMouseAndMouseCursorPosition(1)
                // Pet chases the cursor (window origin is bottom-left; CG y is top-left).
                if let self, let win = self.window {
                    let screenH = NSScreen.screens.first?.frame.height ?? bounds.height
                    let p = CGPoint(x: pos.x - PetWindow.size.width / 2, y: screenH - pos.y - PetWindow.size.height)
                    self.position = p
                    win.setFrameOrigin(p)
                    self.facingRight = dx > 0
                }
                if ticks >= 180 {
                    t.invalidate()
                    self?.hijackTimer = nil
                    self?.say("Thanks for the ride.")
                }
            }
        }
    }

    private func randomPoint(in r: CGRect) -> CGPoint {
        CGPoint(x: .random(in: r.minX + 40...r.maxX - 40), y: .random(in: r.minY + 40...r.maxY - 40))
    }

    // MARK: Desktop icon shuffle (moves icons only, never files; reversible)

    private static let desktopBackup = NSString(string: "~/.chaos_tamagotchi_desktop_positions.txt").expandingTildeInPath

    /// Scatters Finder desktop icons. Original positions are saved once so "Restore Desktop" undoes it.
    func shuffleDesktopIcons() {
        let backup = Self.desktopBackup
        let fresh = !FileManager.default.fileExists(atPath: backup)
        Task.detached {
            if fresh {
                let dump = Self.osascript("""
                tell application "Finder"
                  set out to ""
                  repeat with i in (every item of desktop)
                    set p to desktop position of i
                    set out to out & (name of i) & "|" & (item 1 of p) & "|" & (item 2 of p) & linefeed
                  end repeat
                  return out
                end tell
                """)
                try? dump.write(toFile: backup, atomically: true, encoding: .utf8)
            }
            // Slide every icon toward a random spot in a few visible steps so you can watch it happen.
            _ = Self.osascript("""
            tell application "Finder"
              set b to bounds of window of desktop
              set w to (item 3 of b) - 140
              set h to (item 4 of b) - 140
              repeat with i in (every item of desktop)
                set p to desktop position of i
                set tx to random number from 60 to w
                set ty to random number from 60 to h
                repeat with k from 1 to 8
                  set desktop position of i to {(item 1 of p) + (tx - (item 1 of p)) * k / 8, (item 2 of p) + (ty - (item 2 of p)) * k / 8}
                  delay 0.05
                end repeat
              end repeat
            end tell
            """)
            await MainActor.run { [weak self] in self?.say("Reorganized your desktop. You're welcome.") }
        }
    }

    /// Grabs ONE random desktop folder (or item): the pet walks the cursor to it and drags it across
    /// the screen where you can watch. Icon position only; the file itself is never touched.
    func grabDesktopFolder() {
        let backup = Self.desktopBackup
        let fresh = !FileManager.default.fileExists(atPath: backup)
        Task.detached { [weak self] in
            if fresh {
                let dump = Self.osascript("""
                tell application "Finder"
                  set out to ""
                  repeat with i in (every item of desktop)
                    set p to desktop position of i
                    set out to out & (name of i) & "|" & (item 1 of p) & "|" & (item 2 of p) & linefeed
                  end repeat
                  return out
                end tell
                """)
                try? dump.write(toFile: backup, atomically: true, encoding: .utf8)
            }
            // Prefer folders; fall back to any desktop item.
            let pick = Self.osascript("""
            tell application "Finder"
              set c to every folder of desktop
              if (count of c) is 0 then set c to every item of desktop
              if (count of c) is 0 then return ""
              set i to some item of c
              set p to desktop position of i
              return (name of i) & "|" & (item 1 of p) & "|" & (item 2 of p)
            end tell
            """).trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = pick.components(separatedBy: "|")
            guard parts.count == 3, let x = Double(parts[1]), let y = Double(parts[2]) else { return }
            let name = parts[0]
            let bounds = CGDisplayBounds(CGMainDisplayID())
            let dest = CGPoint(x: .random(in: 120...(bounds.maxX - 200)), y: .random(in: 120...(bounds.maxY - 200)))
            let esc = name.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            await MainActor.run { [weak self] in
                self?.say("Nice folder. It's mine now.", seconds: 4)
                self?.dragCursor(from: CGPoint(x: x, y: y), to: dest, duration: 1.6)
            }
            try? await Task.sleep(for: .milliseconds(900))  // cursor "arrives" at the icon first
            _ = Self.osascript("""
            tell application "Finder"
              set i to item "\(esc)" of desktop
              repeat with k from 1 to 24
                set desktop position of i to {\(x) + (\(dest.x) - \(x)) * k / 24, \(y) + (\(dest.y) - \(y)) * k / 24}
                delay 0.04
              end repeat
            end tell
            """)
            await MainActor.run { [weak self] in
                self?.record("Moved a desktop folder", "\(name) → (\(Int(dest.x)), \(Int(dest.y))). Restore Desktop Icons undoes it.")
            }
        }
    }

    /// Glides the pointer (and the pet) from a to b: a visible "grab and drag" (no clicks).
    private func dragCursor(from a: CGPoint, to b: CGPoint, duration: TimeInterval) {
        var t: Double = 0
        Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                // First 0.9s: fly to the icon. Then drag it to b over the rest.
                t += 1.0 / 60
                let pos: CGPoint
                if t < 0.9 {
                    let cur = CGEvent(source: nil)?.location ?? a
                    let k = t / 0.9
                    pos = CGPoint(x: cur.x + (a.x - cur.x) * k, y: cur.y + (a.y - cur.y) * k)
                } else {
                    let k = min(1, (t - 0.9) / duration)
                    pos = CGPoint(x: a.x + (b.x - a.x) * k, y: a.y + (b.y - a.y) * k)
                }
                CGWarpMouseCursorPosition(pos)
                if let self, let win = self.window {
                    let screenH = NSScreen.screens.first?.frame.height ?? 900
                    let p = CGPoint(x: pos.x - PetWindow.size.width / 2, y: screenH - pos.y - PetWindow.size.height)
                    self.position = p
                    win.setFrameOrigin(p)
                }
                if t >= 0.9 + duration { timer.invalidate() }
            }
        }
    }

    func restoreDesktopIcons() {
        let backup = Self.desktopBackup
        guard let text = try? String(contentsOfFile: backup, encoding: .utf8) else { return }
        Task.detached {
            var script = "tell application \"Finder\"\n"
            for line in text.split(separator: "\n") {
                let parts = line.components(separatedBy: "|")
                guard parts.count == 3, let x = Int(parts[1]), let y = Int(parts[2]) else { continue }
                let name = parts[0].replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
                script += "try\nset desktop position of item \"\(name)\" of desktop to {\(x), \(y)}\nend try\n"
            }
            script += "end tell"
            _ = Self.osascript(script)
            try? FileManager.default.removeItem(atPath: backup)
            await MainActor.run { [weak self] in self?.say("Fine. Desktop restored.") }
        }
    }

    nonisolated static func osascript(_ script: String) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        guard (try? p.run()) != nil else { return "" }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self)
    }

    private func nudgeCursor() {
        guard let current = CGEvent(source: nil)?.location else { return }
        let target = CGPoint(x: current.x + .random(in: -12...12), y: current.y + .random(in: -12...12))
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: target, mouseButton: .left)?
            .post(tap: .cghidEventTap)
    }

    // MARK: Speech

    func say(_ text: String, seconds: TimeInterval = 7) {
        speechTask?.cancel()
        speechText = text
        speechTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            if !Task.isCancelled { self?.speechText = nil }
        }
    }

    nonisolated static func requestLine(system: String, user: String, maxTokens: Int) async -> String? {
        guard let key = appEnvironment["FEATHERLESS_API_KEY"], !key.isEmpty,
              let url = URL(string: "https://api.featherless.ai/v1/chat/completions") else { return nil }
        let model = appEnvironment["FEATHERLESS_MODEL"] ?? "mistralai/Mistral-Nemo-Instruct-2407"
        let body: [String: Any] = [
            "model": model, "temperature": 0.9, "max_tokens": maxTokens,
            "messages": [["role": "system", "content": system], ["role": "user", "content": user]],
        ]
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let msg = choices.first?["message"] as? [String: Any],
              let text = msg["content"] as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines.union(.init(charactersIn: "\"")))
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: Final escalation: the sidecar texts the allowlisted contact (Mateo) as the pet

    /// Menu-bar test hook: run the final escalation immediately.
    func commitCrime() {
        let minutes = Int((deadlineSeconds / 60).rounded())
        let poop = mischiefKit.poopCount
        let situation = "The user ignored their desktop pet for the full \(minutes) minutes. The pet has already pooped on their screen \(poop) times, left sticky notes, shoved their windows around and hijacked their cursor. Now it texts their friend to complain about them."
        say("That's it. I'm doing something about this...", seconds: 5)
        let armed = Self.isArmed
        Task { [weak self] in
            let entry = await Self.runSidecar(situation: situation, armed: armed)
            guard let self else { return }
            NSLog("ChaosTamagotchi sidecar result: %@ | %@", entry.label, entry.outcome)
            self.record(entry.label, entry.outcome)
            self.say("\(entry.label): \(entry.outcome)", seconds: 12)
        }
    }

    nonisolated private static func runSidecar(situation: String, armed: Bool) async -> ChaosLogEntry {
        await Task.detached { () -> ChaosLogEntry in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            p.arguments = ["python3", sidecarScriptPath, situation]
            var env = appEnvironment
            env["PATH"] = sidecarExtraPath + ":" + (env["PATH"] ?? "/usr/bin:/bin")
            env["CHAOS_ARMED"] = armed ? "1" : "0"
            p.environment = env
            let out = Pipe(), err = Pipe()
            p.standardOutput = out
            p.standardError = err
            do {
                try p.run()
            } catch {
                return ChaosLogEntry(date: Date(), label: "Sidecar failed to launch", outcome: "\(error.localizedDescription)")
            }
            // Drain both pipes before waiting so a chatty child can't deadlock.
            let errDrain = Task.detached { err.fileHandleForReading.readDataToEndOfFile() }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            _ = await errDrain.value
            p.waitUntilExit()
            let text = String(decoding: data, as: UTF8.self)
            let last = text.split(separator: "\n").last.map(String.init) ?? ""
            if let d = last.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
               let label = json["label"] as? String, let outcome = json["outcome"] as? String {
                return ChaosLogEntry(date: Date(), label: label, outcome: outcome)
            }
            return ChaosLogEntry(date: Date(), label: "Sidecar error",
                                 outcome: "Unparseable output (exit \(p.terminationStatus)): \(last)")
        }.value
    }
}
