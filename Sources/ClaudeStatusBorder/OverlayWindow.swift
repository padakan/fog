import AppKit
import SwiftUI

/// A transparent, click-through, always-on-top window that covers a whole screen.
final class OverlayWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true            // click-through
        level = .screenSaver                 // above normal windows & menu bar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Non-interactive overlay content: the border glow + the Done sweep.
private struct OverlayRoot: View {
    @ObservedObject var model: StatusModel

    var body: some View {
        ZStack {
            BorderView(model: model)
            if model.state == .done {
                DoneOverlay(color: model.theme.primary, image: model.doneShakeImage)
                    .id(model.doneTick)            // re-trigger the effect each time
            }
        }
    }
}

@MainActor
final class OverlayController {
    private var window: OverlayWindow?
    private let model: StatusModel

    var overlayWindowNumber: Int { window?.windowNumber ?? 0 }

    init(model: StatusModel) {
        self.model = model
        build()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    /// Best-effort read of the display's physical corner radius so the border can
    /// hug the real curve. Falls back to 0 (square) for monitors without rounding.
    static func cornerRadius(of screen: NSScreen) -> CGFloat {
        let sel = NSSelectorFromString("_cornerRadius")
        if screen.responds(to: sel),
           let v = screen.value(forKey: "_cornerRadius") as? CGFloat, v > 1 {
            return v
        }
        return 0
    }

    private func build() {
        guard let screen = NSScreen.main else { return }
        model.screenCornerRadius = Self.cornerRadius(of: screen)
        let win = OverlayWindow(screen: screen)
        let host = NSHostingView(rootView: OverlayRoot(model: model))
        host.frame = win.contentView?.bounds ?? screen.frame
        host.autoresizingMask = [.width, .height]
        win.contentView = host
        win.orderFrontRegardless()
        window = win
    }

    @objc private func screensChanged() {
        guard let screen = NSScreen.main else { return }
        model.screenCornerRadius = Self.cornerRadius(of: screen)
        window?.setFrame(screen.frame, display: true)
    }
}
