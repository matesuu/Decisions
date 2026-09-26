import AppKit
import Combine
import CoreGraphics

// MARK: - Easy-to-edit configuration

/// Path to the Python sidecar script. Edit this to match where the repo lives.
let sidecarScriptPath = "/Users/rahulsuthar/Downloads/Decisions/sidecar/chaos_action.py"

/// GUI apps get a minimal PATH; add the usual places python3 (with deps) lives.
let sidecarExtraPath = "/opt/homebrew/bin:/usr/local/bin:/opt/anaconda3/bin"

/// Default deadline: 30 minutes.
let defaultDeadlineSeconds: TimeInterval = 1800

// MARK: - Model types

enum Mood: String {
    case content, restless, anxious, feral, committingCrimes

    var emoji: String {
        switch self {
        case .content: return "🐥"
        case .restless: return "🐤"
        case .anxious: return "🦆"
        case .feral: return "👹"
        case .committingCrimes: return "😈"
        }
    }
    var symbol: String {
        switch self {
        case .content: return "pawprint.fill"
        case .restless: return "pawprint"
        case .anxious: return "exclamationmark.triangle"
        case .feral: return "flame.fill"
        case .committingCrimes: return "bolt.trianglebadge.exclamationmark.fill"
        }
    }
    var bobSpeed: Double { self == .content ? 3 : 6 }
    var bobAmount: Double { self == .content ? 3 : 2 }
    var shakeAmount: Double {
        switch self {
        case .content, .restless: return 0
        case .anxious: return 1.5
        case .feral, .committingCrimes: return 3.5
        }
    }
    var glitch: Bool { self == .feral || self == .committingCrimes }

    /// Seconds between mischief events; nil = none.
    var mischiefInterval: TimeInterval? {
        switch self {
        case .content: return nil
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

    /// UserDefaults-backed "Chaos Armed" switch. Default OFF.
    static var isArmed: Bool {
        get { UserDefaults.standard.bool(forKey: "chaosArmed") }
        set { UserDefaults.standard.set(newValue, forKey: "chaosArmed") }
    }

    init() {
        let override = ProcessInfo.processInfo.environment["CHAOS_DEBUG_DEADLINE_SECONDS"].flatMap(Double.init)
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

    // MARK: Check-in

    func checkIn() {
        NSLog("ChaosTamagotchi check-in (was %@s left)", String(Int(secondsLeft)))
        elapsed = 0
        secondsLeft = deadlineSeconds
        triggeredThisCycle = false
        sinceMischief = 0
        mood = .content
        say("Nom. Fine. You're forgiven. For now.")
    }

    // MARK: Tick (1 Hz)

    private func tick() {
        elapsed += 1
        secondsLeft = max(0, deadlineSeconds - elapsed)
        let newMood = Mood.from(fraction: elapsed / deadlineSeconds)
        if newMood != mood { mood = newMood }

        // Scale mischief cadence down when the deadline is shortened for debugging.
        let scale = min(1, deadlineSeconds / defaultDeadlineSeconds)
        sinceMischief += 1
        if let interval = mood.mischiefInterval, sinceMischief >= max(3, interval * scale) {
            sinceMischief = 0
            mischief()
        }

        if mood == .committingCrimes && !triggeredThisCycle {
            triggeredThisCycle = true
            commitCrime()
        }
    }

    // MARK: Walking (30 Hz): random walk along the bottom edge

    private func walk(dt: TimeInterval) {
        guard let window else { return }
        let screen = (window.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        directionTimeLeft -= dt
        if directionTimeLeft <= 0 {
            direction = [-1, 0, 1].randomElement()!
            directionTimeLeft = .random(in: 2...6)
        }
        let speed: CGFloat = switch mood {
        case .content: 25
        case .restless: 40
        case .anxious: 60
        case .feral, .committingCrimes: 100
        }
        var p = position
        p.x += direction * speed * dt
        let minX = screen.minX, maxX = screen.maxX - PetWindow.size.width
        if p.x < minX { p.x = minX; direction = 1 }
        if p.x > maxX { p.x = maxX; direction = -1 }
        p.y = screen.minY  // stay on the bottom edge
        if direction != 0 { facingRight = direction > 0 }
        position = p
        window.setFrameOrigin(p)
    }

    // MARK: Mischief (never synthesizes keystrokes into other apps)

    private static let silly: [String] = [
        "https://en.wikipedia.org/wiki/Special:Random",
        "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
        "https://theuselessweb.com/",
        "https://pointerpointer.com/",
    ]

    private func mischief() {
        switch mood {
        case .content: break
        case .restless:
            nudgeCursor()
        case .anxious:
            nudgeCursor()
            fetchFlavorText()
        case .feral, .committingCrimes:
            nudgeCursor()
            fetchFlavorText()
            // Intentionally silly and never destructive: just opens a harmless web page.
            NSWorkspace.shared.open(URL(string: Self.silly.randomElement()!)!)
        }
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

    private static let cannedLines = [
        "I can see you. You're not looking at me.",
        "Feed me or I start touching your things.",
        "Day 1 of being ignored. I am fine. (I am not fine.)",
        "Bold of you to have other priorities.",
    ]

    private func fetchFlavorText() {
        let mood = self.mood
        Task { [weak self] in
            let line = await Self.requestFlavorLine(mood: mood) ?? Self.cannedLines.randomElement()!
            self?.say(line)
        }
    }

    nonisolated private static func requestFlavorLine(mood: Mood) async -> String? {
        guard let key = ProcessInfo.processInfo.environment["FEATHERLESS_API_KEY"], !key.isEmpty,
              let url = URL(string: "https://api.featherless.ai/v1/chat/completions") else { return nil }
        let model = ProcessInfo.processInfo.environment["FEATHERLESS_MODEL"] ?? "meta-llama/Meta-Llama-3.1-8B-Instruct"
        let body: [String: Any] = [
            "model": model,
            "temperature": 1.1,
            "max_tokens": 60,
            "messages": [
                ["role": "system", "content": "You are a needy, passive-aggressive desktop pet. Reply with ONE short sentence (under 15 words), no quotes."],
                ["role": "user", "content": "You are feeling \(mood.rawValue) because your owner ignored you. Say something guilt-tripping and demanding."],
            ],
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

    // MARK: Final escalation: shell out to the Python sidecar

    private func commitCrime() {
        let minutes = Int((deadlineSeconds / 60).rounded())
        let situation = "The user ignored their desktop pet for the full \(minutes) minutes, doing anything else instead of checking in. The pet has had enough."
        say("That's it. I'm doing something about this...", seconds: 5)
        let armed = Self.isArmed
        Task { [weak self] in
            let entry = await Self.runSidecar(situation: situation, armed: armed)
            guard let self else { return }
            NSLog("ChaosTamagotchi sidecar result: %@ | %@", entry.label, entry.outcome)
            self.history.insert(entry, at: 0)
            if self.history.count > 20 { self.history.removeLast(self.history.count - 20) }
            self.say("\(entry.label): \(entry.outcome)", seconds: 12)
        }
    }

    nonisolated private static func runSidecar(situation: String, armed: Bool) async -> ChaosLogEntry {
        await Task.detached { () -> ChaosLogEntry in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            p.arguments = ["python3", sidecarScriptPath, situation]
            var env = ProcessInfo.processInfo.environment
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
