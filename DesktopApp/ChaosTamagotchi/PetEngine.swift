import AppKit
import Combine
import CoreGraphics

// MARK: - Easy-to-edit configuration

/// GUI apps get a minimal PATH; add the usual places python3 (with deps) lives.
let sidecarExtraPath = "/opt/homebrew/bin:/usr/local/bin:/opt/anaconda3/bin"

/// Default hunger cycle: 3 minutes from completely full to empty.
let defaultDeadlineSeconds: TimeInterval = 180

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
        case .content: return nil
        case .restless: return 60
        case .anxious: return 45
        case .feral: return 30
        case .committingCrimes: return 20
        }
    }

    static func from(fraction f: Double) -> Mood {
        switch f {
        case ..<0.15: return .content
        case ..<0.40: return .restless
        case ..<0.75: return .anxious
        case ..<1.0: return .feral
        default: return .committingCrimes
        }
    }
}

/// Short clip that overrides the mood sprite. Feeding plays happy.
enum PetFace: String {
    case happy
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
    @Published private(set) var face: PetFace?
    @Published private(set) var facingRight = false

    /// Debug-only override: set CHAOS_DEBUG_DEADLINE_SECONDS (e.g. 30) in the Xcode scheme
    /// to fast-forward through all moods. Never set in normal use.
    let deadlineSeconds: TimeInterval
    /// Fullness, 0...100. Drains every second, faster the emptier it gets; each click adds 15.
    private var fullness: Double = 100
    private var lastText = Date.distantPast
    private var textInFlight = false
    private let textInterval: TimeInterval = appEnvironment["CHAOS_TEXT_INTERVAL_SECONDS"].flatMap(Double.init) ?? 300
    private var sinceMischief: TimeInterval = 0
    private var direction: CGFloat = -1
    private var directionTimeLeft: TimeInterval = 5
    private var speechTask: Task<Void, Never>?
    private var faceTask: Task<Void, Never>?
    private var tickTimer: Timer?
    private var walkTimer: Timer?
    private weak var window: PetWindow?

    /// UserDefaults-backed "Chaos Armed" switch. Default ON (texts are still pinned to the test contact).
    static var isArmed: Bool {
        get { UserDefaults.standard.bool(forKey: "chaosArmed") }
        set { UserDefaults.standard.set(newValue, forKey: "chaosArmed") }
    }

    /// Safe mode: the pet just roams and says cute things. No hunger, notes, crimes, tabs, music or texts.
    static var isSafeMode: Bool {
        get { UserDefaults.standard.bool(forKey: "safeMode") }
        set { UserDefaults.standard.set(newValue, forKey: "safeMode") }
    }

    func setSafeMode(_ on: Bool) {
        Self.isSafeMode = on
        if on {
            restoreEverything(announce: false)
            say("safe mode. I'm just here to be cute now. 🌸", seconds: 4)
        } else {
            say("safe mode off. hehehe.", seconds: 3)
        }
    }

    /// Undoes everything the pet did: poop, notes, wallpaper, desktop icons, music, its browser tabs, open ultimatum.
    func restoreEverything(announce: Bool = true) {
        hijackTimer?.invalidate()
        hijackTimer = nil
        UltimatumPanel.dismiss()
        ultimatumOpen = false
        let kit = mischiefKit
        kit.cleanAllPoop()
        kit.cleanAllNotes()
        kit.restoreWallpaper(announce: false)
        kit.restoreSpotify()
        kit.closeOpenedTabs()
        kit.restoreWindows()
        restoreDesktopIcons(announce: false)
        if announce { say("everything's back. I was never here.", seconds: 4) }
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

    /// 0...1 fullness.
    var health: Double { max(0, min(1, fullness / 100)) }

    // Hunger drains at a + b·(100 − fullness) %/s: at empty it's `starveSpeedup`× faster than at full,
    // and an ignored pet goes from 100 to 0 in exactly `starveSeconds` (CHAOS_STARVE_SECONDS, default 180).
    private let starveSeconds: TimeInterval = appEnvironment["CHAOS_STARVE_SECONDS"].flatMap(Double.init) ?? 180
    private let starveSpeedup = 10.0
    private var drainB: Double { log(starveSpeedup) / starveSeconds }
    private var drainA: Double { 100 * drainB / (starveSpeedup - 1) }
    private func drainRate(at f: Double) -> Double { drainA + drainB * (100 - f) }

    /// Seconds for an ignored pet to drain from fullness `f` down to `target`.
    private func secondsToDrain(from f: Double, to target: Double) -> TimeInterval {
        guard f > target else { return 0 }
        return log(drainRate(at: target) / drainRate(at: f)) / drainB
    }

    /// Seconds until the next mood tier, and its name (nil once committingCrimes).
    var nextTier: (name: String, seconds: TimeInterval)? {
        for (threshold, name) in [(85.0, "chaos"), (60.0, "anxious"), (25.0, "feral"), (0.0, "crimes")] where fullness > threshold {
            return (name, secondsToDrain(from: fullness, to: threshold))
        }
        return nil
    }

    // MARK: Check-in

    /// One click = one snack: +15% fullness. It never resets the pet; you have to keep feeding it.
    func checkIn() {
        fullness = min(100, fullness + 15)
        updateHunger()
        showFace(.happy, seconds: 0.8)
        if speechText == nil {
            say(["nom.", "+15%. acceptable.", "more.", "that's it?", "snack acquired.", "keep going."].randomElement()!, seconds: 1.5)
        }
    }

    private func updateHunger() {
        secondsLeft = secondsToDrain(from: fullness, to: 0)
        let newMood = Mood.from(fraction: 1 - fullness / 100)
        guard newMood != mood else { return }
        mood = newMood
        if newMood != .content {
            faceTask?.cancel()
            face = nil
        }
    }

    // MARK: Tick (1 Hz)

    private var sinceNote: TimeInterval = 0

    private func tick() {
        // Safe mode: roam and say cute things. Nothing else.
        if Self.isSafeMode {
            fullness = 100
            updateHunger()
            chatter()
            return
        }
        fullness = max(0, fullness - drainRate(at: fullness))
        updateHunger()

        // Scale mischief cadence down when the deadline is shortened for debugging.
        let scale = min(1, deadlineSeconds / 1800)
        sinceMischief += 1
        let due = max(3, (mood.mischiefInterval ?? 0) * scale)
        if mood.mischiefInterval != nil, sinceMischief >= due {
            sinceMischief = 0
            mischief()
        }

        chatter()

        // Chaos starts below 85%: leave a nonsense sticky note about once a minute.
        if mood != .content {
            sinceNote += 1
            if sinceNote >= 60 {
                sinceNote = 0
                mischiefKit.stickyNoteRoast()
            }
        } else {
            sinceNote = 0
        }

        // Mommy ASMR is chaos too, never calm-tier behavior.
        if mood != .content {
            sinceASMR += 1
            if sinceASMR >= nextASMR {
                sinceASMR = 0
                nextASMR = .random(in: 120...240)
                mischiefKit.openMommyASMR()
            }
        } else {
            sinceASMR = 0
        }

        // Feral (25% and below): every 30 seconds, new tabs.
        if mood == .feral || mood == .committingCrimes {
            sinceBarrage += 1
            if sinceBarrage >= 30 {
                sinceBarrage = 0
                feralBarrage()
            }
        } else {
            sinceBarrage = 0
        }

        // Last resort: only at 0%, and at most every CHAOS_TEXT_INTERVAL_SECONDS (default 300), it texts your friend.
        if mood == .committingCrimes && !textInFlight && Date().timeIntervalSince(lastText) >= textInterval {
            lastText = Date()
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
    private var lastSpotify = Date.distantPast
    private var sinceBarrage: TimeInterval = 0
    private var sinceASMR: TimeInterval = 0
    private var nextASMR: TimeInterval = .random(in: 120...240)
    private(set) lazy var mischiefKit = MischiefKit(engine: self)

    /// One stunt the pet can pull. It announces itself in the speech bubble, then does it.
    private struct Crime {
        let name: String
        let weight: Int
        var severe = false  // only severe crimes get a real ultimatum
        let lines: [String]
        let run: @MainActor () -> Void
    }

    private func mischief() {
        let kit = mischiefKit
        // Poop ramps sharply with hunger: both the chance and pile size increase by tier.
        let poop: (chance: Int, count: ClosedRange<Int>) = switch mood {
        case .content: (0, 0...0)
        case .restless: (55, 1...1)
        case .anxious: (75, 1...2)
        case .feral: (100, 2...4)
        case .committingCrimes: (100, 3...5)
        }
        if Int.random(in: 1...100) <= poop.chance {
            kit.dropPoop(count: Int.random(in: poop.count))
        }
        // Mild crimes are the bread and butter; the severe ones unlock as it gets hungrier.
        var pool: [Crime] = [
            Crime(name: "boop your cursor", weight: 4, lines: ["boop.", "your cursor looks lonely.", "don't mind me…"], run: { self.nudgeCursor() }),
        ]
        if mood != .content {
            pool.append(Crime(name: "shove your window", weight: 3, lines: ["this window's in my spot.", "scoot.", "rearranging. hold still."], run: { kit.nudgeFrontWindow() }))
            pool.append(Crime(name: "hijack your mouse", weight: 2, severe: true, lines: ["gimme the mouse.", "my turn to drive.", "MINE."], run: { self.hijackCursor() }))
            if Date().timeIntervalSince(lastSpotify) > 60 {
                pool.append(Crime(name: "pick the music", weight: 1, severe: true, lines: ["let me pick the music. 🎶", "DJ time."], run: { self.lastSpotify = Date(); kit.spotifyRevenge() }))
            }
        }
        if mood == .anxious || mood == .feral || mood == .committingCrimes {
            pool.append(Crime(name: "steal a folder", weight: 2, severe: true, lines: ["ooh, a folder.", "that folder? mine now.", "redecorating your desktop."], run: { self.grabDesktopFolder() }))
        }
        let draw = { () -> Crime in
            var roll = Int.random(in: 0..<pool.reduce(0) { $0 + $1.weight })
            return pool.first { roll -= $0.weight; return roll < 0 } ?? pool[0]
        }
        let crime = draw()
        // Severe crimes sometimes come as an ultimatum: pick one or she does both.
        if mood != .content, !ultimatumOpen, crime.severe, Bool.random(),
           let other = pool.filter({ $0.severe && $0.name != crime.name }).randomElement() {
            ultimatumOpen = true
            say("ultimatum. pick one.", seconds: 3)
            UltimatumPanel.show(near: position, a: crime.name, b: other.name, seconds: 8) { [weak self] choice in
                guard let self else { return }
                self.ultimatumOpen = false
                switch choice {
                case 0: self.announce("fine. \(crime.name).", then: crime.run)
                case 1: self.announce("fine. \(other.name).", then: other.run)
                default:
                    self.record("Ignored an ultimatum", "Didn't pick between \(crime.name) and \(other.name). Got both.", show: false)
                    self.announce("you didn't pick. both.", then: { crime.run(); self.after(2.5, other.run) })
                }
            }
            return
        }
        // Otherwise, now and then, a fake ultimatum with outrageous threats that ends in one big poop.
        if mood != .content, !ultimatumOpen, Int.random(in: 0..<8) == 0 {
            fakeoutUltimatum()
            return
        }
        announce(crime.lines.randomElement()!, then: crime.run)
    }

    private var ultimatumOpen = false

    /// The every-30-seconds feral routine: a new Mommy ASMR tab, then a random Google Images tab.
    private func feralBarrage() {
        let kit = mischiefKit
        kit.openMommyASMR()
        after(4) { kit.openRandomImages() }
    }

    /// Fake threats for the fakeout ultimatum when the LLM is unavailable.
    nonisolated private static let cannedFakeThreats = [
        "send your nudes to your mom", "push your API keys to GitHub", "text your ex \"u up?\"",
        "reply-all \"I quit\"", "post your search history", "email your boss your diary",
        "tweet your passwords", "venmo your ex $1 with a ❤️", "rename every file to \"final_final\"",
        "set your ringtone to your voice memos",
    ]

    /// Presents two AI-written outrageous threats as an ultimatum, then reveals it was a joke and drops a big poop.
    func fakeoutUltimatum() {
        guard !ultimatumOpen else { return }
        ultimatumOpen = true
        say("hmm. I have an idea.", seconds: 3)
        Task { [weak self] in
            let (a, b) = await Self.fakeThreats()
            guard let self else { return }
            self.say("ultimatum. pick one.", seconds: 3)
            UltimatumPanel.show(near: self.position, a: a, b: b, seconds: 8) { [weak self] choice in
                guard let self else { return }
                self.ultimatumOpen = false
                self.say(choice == nil ? "no answer? …jk. have this instead." : "lol jk. have this instead.", seconds: 4)
                self.after(1.2) { self.mischiefKit.dropPoop(count: 1, scale: 2) }
                self.record("Fakeout ultimatum", "Threatened to \(a) or \(b). Just pooped instead.", show: false)
            }
        }
    }

    nonisolated private static func fakeThreats() async -> (String, String) {
        let text = await requestLine(
            system: "You are a chaotic desktop pet bluffing your owner with an ultimatum. Invent TWO different outrageous, "
                + "embarrassing things you threaten to do on their computer (e.g. \"send your nudes to your mom\", "
                + "\"push your API keys to GitHub\"). Each is a lowercase verb phrase under 7 words, addressed to \"you/your\". "
                + "Output exactly two lines, nothing else.",
            user: "Give me two new ones.", maxTokens: 50) ?? ""
        let lines = text.split(whereSeparator: \.isNewline)
            .map { $0.replacingOccurrences(of: #"^\s*(?:[-*•]|\d+[.)]|[AB][.):])\s*"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces.union(.init(charactersIn: "\"."))) }
            .filter { !$0.isEmpty && $0.count <= 48 }
        if lines.count >= 2, lines[0] != lines[1] { return (lines[0], lines[1]) }
        let canned = cannedFakeThreats.shuffled()
        return (canned[0], canned[1])
    }

    /// Says what she's about to do, waits a beat so you can read it, then does it.
    private func announce(_ line: String, then action: @escaping @MainActor () -> Void) {
        say(line, seconds: 3)
        after(1.6, action)
    }

    // MARK: Idle chatter: tiny bubbles so it feels like a pet

    private var sinceChatter: TimeInterval = 0
    private var nextChatter: TimeInterval = .random(in: 12...25)

    private func chatter() {
        sinceChatter += 1
        guard speechText == nil, sinceChatter >= nextChatter else { return }
        sinceChatter = 0
        nextChatter = .random(in: 14...30)
        let chaos: [String] = switch mood {
            case .content: ["the walls are listening. to me. finally.", "I licked the wifi.", "do you ever just vibrate.",
                            "I am 40% soup.", "who moved the moon.", "prrr"]
            case .restless: ["Tuesday is coming. act natural.", "the cursor knows.", "I invented jazz.", "feed me or I tell the pigeons."]
            case .anxious: ["my lawyer is a pigeon.", "the fridge is plotting.", "HELLO??", "I can hear the pixels."]
            case .feral, .committingCrimes: ["hehehe", "no rules.", "the geese have spoken.", "you did this.", "*gremlin noises*"]
            }
        let lines = Self.isSafeMode || mood == .content
            ? ["hi :3", "you're doing great!", "prrr", "I like it here.", "nice screen!", "you're my favorite human.",
               "*happy wiggle*", "drink some water! 💧", "proud of you.", "*purrs quietly*"]
            : chaos
        say(lines.randomElement()!, seconds: 2.5)
    }

    private func after(_ seconds: TimeInterval, _ block: @escaping @MainActor () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { MainActor.assumeIsolated { block() } }
    }

    /// Logs what the pet did (Console.app, filter "ChaosTamagotchi").
    func record(_ label: String, _ outcome: String, show: Bool = true) {
        NSLog("ChaosTamagotchi %@: %@", label, outcome)
    }

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

    func restoreDesktopIcons(announce: Bool = true) {
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
            if announce { await MainActor.run { [weak self] in self?.say("Fine. Desktop restored.") } }
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

    func showFace(_ face: PetFace, seconds: TimeInterval) {
        faceTask?.cancel()
        self.face = face
        faceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            if !Task.isCancelled { self?.face = nil }
        }
    }

    func say(_ text: String, seconds: TimeInterval = 7) {
        speechTask?.cancel()
        speechText = text
        speechTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            if !Task.isCancelled { self?.speechText = nil }
        }
    }

    /// Appended to every LLM system prompt so all generated lines share one voice.
    nonisolated static let llmVoice = " Voice: satirical and gloriously dumb. Deliver it with total deadpan confidence "
        + "and completely broken logic, like a very stupid pet who is sure it's a genius. Witty, but idiotic: "
        + "absurd non-sequiturs, wrong conclusions, fake facts stated proudly."

    nonisolated static func requestLine(system: String, user: String, maxTokens: Int) async -> String? {
        guard let key = appEnvironment["FEATHERLESS_API_KEY"], !key.isEmpty,
              let url = URL(string: "https://api.featherless.ai/v1/chat/completions") else { return nil }
        let model = appEnvironment["FEATHERLESS_MODEL"] ?? "mistralai/Mistral-Nemo-Instruct-2407"
        let body: [String: Any] = [
            "model": model, "temperature": 0.9, "max_tokens": maxTokens,
            "messages": [["role": "system", "content": system + llmVoice], ["role": "user", "content": user]],
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
        say(["texting your friend.", "your friend needs to hear this.", "sending a message. don't worry about it."].randomElement()!, seconds: 4)
        let armed = Self.isArmed
        textInFlight = true
        Task { [weak self] in
            let entry = await Self.runSidecar(situation: situation, armed: armed)
            guard let self else { return }
            self.textInFlight = false
            NSLog("ChaosTamagotchi sidecar result: %@ | %@", entry.label, entry.outcome)
            self.record(entry.label, entry.outcome)
            self.say(entry.outcome.hasPrefix("[FAILED]") ? "ugh. it didn't send." : entry.outcome.hasPrefix("[DRY RUN]") ? "(pretend I just texted them.)" : "done. they know now. 😈", seconds: 5)
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
