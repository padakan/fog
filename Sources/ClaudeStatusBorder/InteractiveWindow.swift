import AppKit
import SwiftUI
import Carbon.HIToolbox

/// Borderless window that DOES accept mouse events, sized snugly to its content so
/// it never blocks clicks elsewhere. Hosts the waiting modal and the done pill.
final class InteractiveWindow: NSWindow {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver + 1
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }
}

@MainActor
final class InteractiveController {
    private let model: StatusModel
    private let window = InteractiveWindow()
    private let host = NSHostingController(rootView: AnyView(EmptyView()))

    /// The app that was frontmost (the terminal running Claude Code) before we showed UI.
    private var previousApp: NSRunningApplication?
    /// The app you're actually chatting in — captured while thinking/working.
    private var chatHostApp: NSRunningApplication?
    private var doneToken = 0
    private var activationObserver: NSObjectProtocol?

    init(model: StatusModel) {
        self.model = model
        window.contentViewController = host

        // Auto-dismiss the Done pill once you switch back to the chat app.
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, self.model.state == .done else { return }
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                if self.isSameApp(app, self.chatHostApp) {
                    self.model.goIdle()
                    self.hide()
                }
            }
        }
    }

    private func isSameApp(_ a: NSRunningApplication?, _ b: NSRunningApplication?) -> Bool {
        guard let a, let b else { return false }
        if let ba = a.bundleIdentifier, let bb = b.bundleIdentifier { return ba == bb }
        return a.processIdentifier == b.processIdentifier
    }

    /// Called by the AppDelegate after the model updates.
    /// `preview` = triggered from the menu-bar popover (don't touch chat-host tracking,
    /// and always show the UI so it can be seen).
    func update(preview: Bool = false) {
        let front = NSWorkspace.shared.frontmostApplication
        switch model.state {
        case .thinking, .working:
            if !preview { chatHostApp = front }   // remember where you're driving the agent
            hide()
        case .waiting:
            previousApp = front
            // If you're already looking at the chat app, skip the dialog (sound + border only).
            if !preview && isSameApp(front, chatHostApp) {
                hide()
            } else {
                showWaiting()
            }
        case .done:
            previousApp = front
            scheduleDonePill(preview: preview)
        case .idle:
            hide()
        }
    }

    // MARK: Waiting

    private func showWaiting() {
        let tint = model.theme.primary
        let view = WaitingModalView(
            question: model.question,
            options: model.options,
            tint: tint,
            onOption: { [weak self] i in self?.answer(index: i) },
            onFocus: { [weak self] in self?.focusPreviousApp(); self?.hide() },
            onDismiss: { [weak self] in self?.hide() }
        )
        present(AnyView(view), edgeGap: 0)
    }

    // MARK: Done

    private func scheduleDonePill(preview: Bool = false) {
        hide()                       // clear any lingering waiting modal at once
        doneToken &+= 1
        let token = doneToken
        // Let the sweep play first, then pop the pill.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self, self.doneToken == token, self.model.state == .done else { return }
            // Already looking at the chat app? The sweep + sound are enough — no pill.
            if !preview && self.isSameApp(NSWorkspace.shared.frontmostApplication, self.chatHostApp) { return }
            let tint = self.model.theme.primary
            let view = DonePillView(
                tint: tint,
                onOpen: { [weak self] in self?.focusPreviousApp(); self?.model.goIdle(); self?.hide() },
                onDismiss: { [weak self] in self?.model.goIdle(); self?.hide() }
            )
            self.present(AnyView(view), edgeGap: 0)
        }
    }

    // MARK: Window plumbing

    private func present(_ view: AnyView, edgeGap: CGFloat) {
        // Transparent margin so the drop shadow fades out fully inside the window
        // instead of being clipped into a faint gray rectangle.
        host.rootView = AnyView(view.padding(40))
        host.view.layoutSubtreeIfNeeded()
        let size = host.view.fittingSize

        guard let screen = NSScreen.main else { return }
        let f = screen.frame
        // Sit just below the menu bar rather than flush against the very top edge.
        let menuBarHeight = max(0, f.maxY - screen.visibleFrame.maxY)
        let x = f.midX - size.width / 2
        let y = f.maxY - size.height - menuBarHeight - edgeGap
        window.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        window.orderFrontRegardless()
    }

    private func hide() {
        window.orderOut(nil)
        host.rootView = AnyView(EmptyView())
    }

    // MARK: Actions

    private func focusPreviousApp() {
        previousApp?.activate()
    }

    /// Best-effort answer: focus the terminal and type the option number + Return.
    /// Needs Accessibility permission to post keystrokes to another app.
    private func answer(index: Int) {
        focusPreviousApp()
        let keys = "\(index + 1)"
        hide()
        guard ensureAccessibility() else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            Keyboard.type(keys)
            Keyboard.pressReturn()
        }
    }

    @discardableResult
    private func ensureAccessibility() -> Bool {
        let opts = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }
}

/// Posts synthetic keystrokes to the frontmost app.
enum Keyboard {
    static func type(_ text: String) {
        let src = CGEventSource(stateID: .combinedSessionState)
        var chars = Array(text.utf16)
        if let down = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true) {
            down.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: &chars)
            down.post(tap: .cghidEventTap)
        }
        if let up = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false) {
            up.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: &chars)
            up.post(tap: .cghidEventTap)
        }
    }

    static func pressReturn() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let key = CGKeyCode(kVK_Return)
        CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: true)?.post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: false)?.post(tap: .cghidEventTap)
    }
}
