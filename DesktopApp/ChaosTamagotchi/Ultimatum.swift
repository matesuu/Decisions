import AppKit
import SwiftUI

/// "Pick one or I do both": a small floating card next to the pet with two crime buttons and a
/// countdown. Completion gets 0 or 1 for a pick, nil if the timer ran out.
@MainActor
enum UltimatumPanel {
    private static var current: NSPanel?

    static func show(near petOrigin: CGPoint, a: String, b: String, seconds: Double, completion: @escaping (Int?) -> Void) {
        current?.close()
        let size = CGSize(width: 236, height: 150)
        let screen = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        var origin = CGPoint(x: petOrigin.x + PetWindow.size.width - 20, y: petOrigin.y + 40)
        if origin.x + size.width > screen.maxX { origin.x = petOrigin.x - size.width + 20 }
        origin.x = min(max(origin.x, screen.minX + 8), screen.maxX - size.width - 8)
        origin.y = min(max(origin.y, screen.minY + 8), screen.maxY - size.height - 8)

        let panel = NSPanel(contentRect: NSRect(origin: origin, size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        var finished = false
        let finish: (Int?) -> Void = { choice in
            guard !finished else { return }
            finished = true
            panel.close()
            if current === panel { current = nil }
            completion(choice)
        }
        panel.contentView = NSHostingView(rootView: UltimatumView(a: a, b: b, seconds: seconds, pick: finish))
        current = panel
        panel.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { MainActor.assumeIsolated { finish(nil) } }
    }
}

private struct UltimatumView: View {
    let a: String
    let b: String
    let seconds: Double
    let pick: (Int?) -> Void
    @State private var drain = false

    private let rust = Color(red: 0.70, green: 0.35, blue: 0.20)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("ULTIMATUM").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(rust)
                Spacer()
                Text("or I do both").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            }
            option(a, index: 0)
            option(b, index: 1)
            GeometryReader { g in
                Capsule().fill(Color.black.opacity(0.08))
                    .overlay(alignment: .leading) {
                        Capsule().fill(rust).frame(width: drain ? 0 : g.size.width)
                    }
            }
            .frame(height: 3)
        }
        .padding(12)
        .frame(width: 236, height: 150)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.black.opacity(0.08)))
        .shadow(color: .black.opacity(0.22), radius: 10, y: 4)
        .padding(1)
        .onAppear { withAnimation(.linear(duration: seconds)) { drain = true } }
    }

    private func option(_ title: String, index: Int) -> some View {
        Button { pick(index) } label: {
            HStack {
                Text(index == 0 ? "A" : "B").font(.system(size: 10, weight: .bold, design: .monospaced))
                    .frame(width: 18, height: 18)
                    .background(RoundedRectangle(cornerRadius: 5).fill(rust.opacity(0.12)))
                    .foregroundStyle(rust)
                Text(title).font(.system(size: 12.5, weight: .semibold, design: .rounded)).foregroundStyle(.black)
                    .lineLimit(2).minimumScaleFactor(0.75)
                Spacer()
            }
            .padding(.horizontal, 8).frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.black.opacity(0.04)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
