import AppKit
import SwiftUI

/// Hosting view that never lets AppKit's background-drag swallow clicks;
/// PetWindow handles click vs. drag itself.
private final class PetHostingView<Content: View>: NSHostingView<Content> {
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class PetWindow: NSWindow {
    static let size = CGSize(width: 210, height: 210)  // speech bubble + Mona, with room to shake

    /// Called when the user clicks (without dragging) the pet.
    var onClick: (() -> Void)?
    /// Called while the user drags the pet; passes the new window origin.
    var onDrag: ((CGPoint) -> Void)?

    private var dragStartMouse: NSPoint?
    private var dragStartOrigin: NSPoint?
    private var didDrag = false

    init(engine: PetEngine) {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = CGPoint(x: screen.maxX - Self.size.width - 20, y: screen.minY)
        super.init(contentRect: NSRect(origin: origin, size: Self.size),
                   styleMask: [.borderless], backing: .buffered, defer: false)
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        contentView = PetHostingView(rootView: PetView(engine: engine))
        onClick = { [weak engine] in engine?.checkIn() }
        onDrag = { [weak engine] p in engine?.position = p }
    }

    override var canBecomeKey: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            dragStartMouse = NSEvent.mouseLocation
            dragStartOrigin = frame.origin
            didDrag = false
        case .leftMouseDragged:
            if let m0 = dragStartMouse, let o0 = dragStartOrigin {
                let m = NSEvent.mouseLocation
                let dx = m.x - m0.x, dy = m.y - m0.y
                if didDrag || hypot(dx, dy) > 3 {
                    didDrag = true
                    let p = CGPoint(x: o0.x + dx, y: o0.y + dy)
                    setFrameOrigin(p)
                    onDrag?(p)
                }
            }
        case .leftMouseUp:
            if !didDrag { onClick?() }
            dragStartMouse = nil
            didDrag = false
        default:
            super.sendEvent(event)
        }
    }
}
