import SwiftUI

struct PetView: View {
    @ObservedObject var engine: PetEngine

    var body: some View {
        VStack(spacing: 2) {
            SpeechBubble(text: engine.speechText)
                .frame(height: 64, alignment: .bottom)
            Sprite(mood: engine.mood, facingRight: engine.facingRight)
                .frame(width: 90, height: 70)
        }
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

private struct Sprite: View {
    let mood: Mood
    let facingRight: Bool

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let bob = sin(t * mood.bobSpeed) * mood.bobAmount
            let shake = mood.shakeAmount > 0 ? sin(t * 47) * mood.shakeAmount : 0
            let glitching = mood.glitch && Int(t * 10) % 4 == 0

            Text(mood.emoji)
                .font(.system(size: 52))
                .scaleEffect(x: facingRight ? -1 : 1, y: 1)  // the emoji faces left by default
                .offset(x: shake + (glitching ? CGFloat.random(in: -8...8) : 0), y: bob)
                .hueRotation(.degrees(glitching ? Double.random(in: 0...360) : 0))
                .overlay(alignment: .topTrailing) {
                    if mood.glitch { Text("⚡️").font(.system(size: 18)).offset(x: 8, y: -4) }
                }
        }
    }
}
