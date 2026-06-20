import AppKit
import SwiftUI
import UserNotifications

let kStatusPort: UInt16 = 7842

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = StatusModel.shared
    private var overlay: OverlayController?
    private var interactive: InteractiveController?
    private var server: StatusServer?
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var mouseMonitors: [Any] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        overlay = OverlayController(model: model)
        interactive = InteractiveController(model: model)
        setupStatusItem()
        OnboardingController.shared.onPreview = { [weak self] in self?.onboardingPreview($0) }
        OnboardingController.shared.showIfNeeded()   // first-run: explains + requests permissions

        server = StatusServer(port: kStatusPort) { [weak self] update in
            Task { @MainActor in self?.handle(update) }
        }
        server?.start()

        setupMouseTracking()

        // Quietly check for a new release a few seconds after launch (if enabled).
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            if UserDefaults.standard.object(forKey: "autoUpdate") as? Bool ?? true {
                Updater.shared.checkForUpdates(userInitiated: false)
            }
        }
    }

    private func setupMouseTracking() {
        let moveEvents: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        let global = NSEvent.addGlobalMonitorForEvents(matching: moveEvents) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateCursor() }
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: moveEvents) { [weak self] e in
            MainActor.assumeIsolated { self?.updateCursor() }
            return e
        }
        // A click in another app (e.g. clicking the chat's text box) dismisses the Done pill.
        let click = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.interactive?.dismissDonePillOnClickInChatApp() }
        }
        mouseMonitors = [global, local, click].compactMap { $0 }
        updateCursor()
    }

    private func updateCursor() {
        let m = NSEvent.mouseLocation
        guard let f = NSScreen.main?.frame else { return }
        if NSMouseInRect(m, f, false) {
            model.cursorLocation = CGPoint(x: m.x - f.minX, y: f.maxY - m.y)  // flip to top-left
        } else {
            model.cursorLocation = CGPoint(x: -1000, y: -1000)
        }
    }

    private func handle(_ update: StatusUpdate, preview: Bool = false) {
        if update.state == .done {
            model.doneShakeImage = ScreenCapture.grabBelow(window: overlay?.overlayWindowNumber ?? 0)
            if model.soundEnabled { SoundPlayer.shared.play("done") }
        } else if update.state == .waiting {
            if model.soundEnabled { SoundPlayer.shared.play("waiting") }
        }
        model.apply(update)
        interactive?.update(preview: preview)
        if update.notify == true {
            notify(
                title: update.notifyTitle ?? "Claude",
                body: update.notifyBody ?? update.detail ?? update.state.title
            )
        }
    }

    // MARK: Menu bar item (popover)

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = menuBarIconImage()    // template glyph: visible on light & dark bars
        item.button?.action = #selector(togglePopover)
        item.button?.target = self
        statusItem = item

        popover.behavior = .transient
        let picker = ThemePicker(
            model: model,
            onPreview: { [weak self] state in self?.preview(state) },
            version: Updater.shared.currentVersion,
            onCheckUpdates: { Updater.shared.checkForUpdates(userInitiated: true) }
        )
        popover.contentViewController = NSHostingController(rootView: picker)
    }

    /// Manually drive a state for previewing/testing from the menu-bar popover.
    private func previewUpdate(_ state: ClaudeState) -> StatusUpdate {
        var update = StatusUpdate(state: state)
        if state == .waiting {
            update.question = "Example — this is how Claude asks when it needs your input."
            update.options = ["Looks good", "Not now"]
        }
        return update
    }

    /// Menu-bar popover preview — auto-returns to idle after ~5s.
    private func preview(_ state: ClaudeState) {
        handle(previewUpdate(state), preview: true)
        if state == .thinking || state == .working {
            model.startPreviewIdle(seconds: 5)
        }
    }

    /// Onboarding preview — border persists while on the step (no auto-idle).
    private func onboardingPreview(_ state: ClaudeState) {
        handle(previewUpdate(state), preview: true)
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    /// A monochrome template glyph echoing the Fog logo's winking face. Template
    /// images auto-adapt to the menu-bar appearance (dark = white, light = black),
    /// so it's always visible — unlike the black-backed full-color app icon.
    private func menuBarIconImage() -> NSImage {
        // Prefer the real Fog logo (monochrome SVG) as a template.
        if let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "svg"),
           let svg = NSImage(contentsOf: url), svg.isValid {
            svg.size = NSSize(width: 18, height: 18)
            svg.isTemplate = true
            return svg
        }
        // Fallback: a hand-drawn winking face.
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()

            // Smile (concave-up arc).
            let smile = NSBezierPath()
            smile.lineWidth = 2; smile.lineCapStyle = .round
            smile.move(to: NSPoint(x: 4.8, y: 8))
            smile.curve(to: NSPoint(x: 13.2, y: 8),
                        controlPoint1: NSPoint(x: 7.0, y: 4.4),
                        controlPoint2: NSPoint(x: 11.0, y: 4.4))
            smile.stroke()

            // Left eye (open) — vertical bar.
            let left = NSBezierPath()
            left.lineWidth = 2; left.lineCapStyle = .round
            left.move(to: NSPoint(x: 6.6, y: 10.6))
            left.line(to: NSPoint(x: 6.6, y: 14.2))
            left.stroke()

            // Right eye (wink) — downward chevron.
            let wink = NSBezierPath()
            wink.lineWidth = 2; wink.lineCapStyle = .round; wink.lineJoinStyle = .round
            wink.move(to: NSPoint(x: 9.8, y: 13.4))
            wink.line(to: NSPoint(x: 11.6, y: 11.8))
            wink.line(to: NSPoint(x: 13.4, y: 13.4))
            wink.stroke()

            return true
        }
        img.isTemplate = true
        return img
    }

    // MARK: Notifications

    private func notify(title: String, body: String) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
