import AppKit
import ImageIO
import SwiftUI

struct PetView: View {
    @ObservedObject var engine: PetEngine

    var body: some View {
        VStack(spacing: 2) {
            SpeechBubble(text: engine.speechText)
                .frame(height: 64, alignment: .bottom)
            Sprite(mood: engine.mood, facingRight: engine.facingRight, face: engine.face, speaking: engine.speechText != nil)
        }
        .padding(.bottom, 18)
        .frame(width: PetWindow.size.width, height: PetWindow.size.height, alignment: .bottom)
    }
}

private struct SpeechBubble: View {
    let text: String?

    var body: some View {
        ZStack {
            if let text {
                Text(text)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.black)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(.white))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(.black.opacity(0.4), lineWidth: 1))
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: text)
    }
}

/// One frame of mood motion, layered on top of Mona's own hop loop.
private struct SpritePose {
    var x: CGFloat = 0
    var y: CGFloat = 0
    var rotation: Double = 0
    var scaleX: CGFloat = 1
    var scaleY: CGFloat = 1
    var red: Double = 1
    var green: Double = 1
    var blue: Double = 1
    var opacity: Double = 1
}

private extension Mood {
    /// Multiplier on the GIF's native frame timing. Content is lazy; crimes is frantic.
    var playbackRate: Double {
        switch self {
        case .content: 0.55
        case .restless: 1
        case .anxious: 1.35
        case .feral: 1.7
        case .committingCrimes: 2.2
        }
    }

    var showsBolt: Bool { self == .feral || self == .committingCrimes }

    func pose(at t: TimeInterval) -> SpritePose {
        switch self {
        case .content:
            let breathe = CGFloat(1 + sin(t * 1.3) * 0.03)
            return SpritePose(scaleX: breathe, scaleY: breathe)
        case .restless:
            let sway = sin(t * 2.4)
            return SpritePose(x: CGFloat(sway * 8), rotation: sway * 12)
        case .anxious:
            let shiver = sin(t * 36)
            let squash = sin(t * 8)
            return SpritePose(
                x: CGFloat(shiver * 2.6),
                y: CGFloat(sin(t * 5) * 1.4),
                rotation: shiver * 4,
                scaleX: CGFloat(1 + squash * 0.08),
                scaleY: CGFloat(1 - squash * 0.08)
            )
        case .feral:
            let popping = Int(t * 10) % 4 == 0
            return SpritePose(
                x: CGFloat(sin(t * 17) * 6) + (popping ? CGFloat.random(in: -14...14) : 0),
                y: popping ? CGFloat.random(in: -12...4) : CGFloat(sin(t * 7) * 2),
                rotation: sin(t * 9) * 16 + (popping ? Double.random(in: -14...14) : 0),
                scaleX: popping ? 1.14 : 1,
                scaleY: popping ? 0.86 : 1,
                red: popping ? Double.random(in: 0.35...1) : 1,
                green: popping ? Double.random(in: 0.15...1) : 1,
                blue: popping ? Double.random(in: 0.15...1) : 1,
                opacity: popping ? 0.8 : 1
            )
        case .committingCrimes:
            let pulse = (sin(t * 10) + 1) / 2
            let strobe = Int(t * 16) % 5 == 0
            return SpritePose(
                x: CGFloat(sin(t * 48) * 8),
                y: CGFloat(sin(t * 8) * 5),
                rotation: sin(t * 5) * 28,
                scaleX: CGFloat(1.16 + sin(t * 11) * 0.09),
                scaleY: CGFloat(1.16 - sin(t * 11) * 0.09),
                red: 1,
                green: 0.22 + (1 - pulse) * 0.78,
                blue: 0.25 + (1 - pulse) * 0.75,
                opacity: strobe ? 0.5 : 1
            )
        }
    }
}

/// Which Mona GIF is on screen. Built from the hop in `mona-loading-default.gif`.
private enum MonaClip: String, CaseIterable {
    case content = "mona-content"
    case restless = "mona-restless"
    case anxious = "mona-anxious"
    case feral = "mona-feral"
    case crimes = "mona-crimes"
    case happy = "mona-happy"
    case talk = "mona-talk"
    case sad = "mona-sad"

    static func select(mood: Mood, face: PetFace?, speaking: Bool) -> MonaClip {
        if face == .happy { return .happy }
        if speaking, mood == .content || mood == .restless { return .talk }
        switch mood {
        case .content: return .content
        case .restless: return .restless
        case .anxious: return .anxious
        case .feral: return .feral
        case .committingCrimes: return .crimes
        }
    }

    func rate(for mood: Mood) -> Double {
        switch self {
        case .talk: 1.7
        case .happy: 1.1
        default: mood.playbackRate
        }
    }
}

private struct SpriteSheet {
    let frames: [NSImage]
    let delays: [TimeInterval]

    func index(at time: TimeInterval, rate: Double) -> Int {
        guard !frames.isEmpty else { return 0 }
        let duration = delays.reduce(0, +)
        guard duration > 0 else { return 0 }
        var elapsed = (time * rate).truncatingRemainder(dividingBy: duration)
        if elapsed < 0 { elapsed += duration }
        var acc = 0.0
        for (i, delay) in delays.enumerated() {
            acc += delay
            if elapsed < acc { return min(i, frames.count - 1) }
        }
        return frames.count - 1
    }

    static func load(named name: String) -> SpriteSheet {
        let url = Bundle.main.url(forResource: name, withExtension: "gif")
            ?? Bundle.main.url(forResource: "mona-loading-default", withExtension: "gif")
        guard let url, let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            NSLog("ChaosTamagotchi missing %@.gif", name)
            return SpriteSheet(frames: [], delays: [])
        }
        var images: [NSImage] = []
        var times: [TimeInterval] = []
        for i in 0..<CGImageSourceGetCount(source) {
            guard let cg = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
            let size = NSSize(width: CGFloat(cg.width), height: CGFloat(cg.height))
            images.append(NSImage(cgImage: cg, size: size))
            times.append(delay(source: source, index: i))
        }
        return SpriteSheet(frames: images, delays: times)
    }

    private static func delay(source: CGImageSource, index: Int) -> TimeInterval {
        let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
        let gif = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        let raw = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
            ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double)
            ?? 0.16
        return raw < 0.02 ? 0.1 : raw
    }
}

private enum MonaLibrary {
    static let sheets: [MonaClip: SpriteSheet] = Dictionary(
        uniqueKeysWithValues: MonaClip.allCases.map { ($0, SpriteSheet.load(named: $0.rawValue)) }
    )
}

private struct Sprite: View {
    let mood: Mood
    let facingRight: Bool
    let face: PetFace?
    let speaking: Bool

    var body: some View {
        let clip = MonaClip.select(mood: mood, face: face, speaking: speaking)
        let sheet = MonaLibrary.sheets[clip] ?? SpriteSheet(frames: [], delays: [])
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let pose = mood.pose(at: t)
            let idx = sheet.index(at: t, rate: clip.rate(for: mood))
            let image = sheet.frames.indices.contains(idx) ? sheet.frames[idx] : NSImage()

            Image(nsImage: image)
                .resizable()
                .interpolation(.none)
                .antialiased(false)
                .frame(width: 96, height: 96)
                .colorMultiply(Color(red: pose.red, green: pose.green, blue: pose.blue))
                .scaleEffect(x: (facingRight ? -1 : 1) * pose.scaleX, y: pose.scaleY)
                .rotationEffect(.degrees(pose.rotation))
                .offset(x: pose.x, y: pose.y)
                .opacity(pose.opacity)
                .overlay(alignment: .topTrailing) {
                    if mood.showsBolt {
                        Text("⚡️").font(.system(size: 18)).offset(x: 10, y: -6)
                    }
                }
        }
    }
}
