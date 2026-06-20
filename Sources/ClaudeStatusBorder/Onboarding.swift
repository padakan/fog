import SwiftUI
import AppKit
import Combine
import UserNotifications
import ApplicationServices

// MARK: - Permissions

@MainActor
final class PermissionsModel: ObservableObject {
    @Published var notifications = false
    @Published var screenRecording = false
    @Published var accessibility = false

    func refresh() {
        screenRecording = CGPreflightScreenCaptureAccess()
        accessibility = AXIsProcessTrusted()
        UNUserNotificationCenter.current().getNotificationSettings { s in
            Task { @MainActor in self.notifications = (s.authorizationStatus == .authorized) }
        }
    }

    func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
            Task { @MainActor in self.refresh() }
        }
    }

    func requestScreenRecording() {
        _ = CGRequestScreenCaptureAccess()
        refresh()
    }

    func requestAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        refresh()
    }
}

// MARK: - Window + controller

final class OnboardingWindow: NSWindow {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 560),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isMovableByWindowBackground = true
        backgroundColor = NSColor(srgbRed: 0.08, green: 0.08, blue: 0.09, alpha: 1)
        isReleasedWhenClosed = false
        center()
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class OnboardingController {
    static let shared = OnboardingController()
    private var window: OnboardingWindow?
    var onPreview: (ClaudeState) -> Void = { _ in }   // set by AppDelegate to drive the real overlay

    func showIfNeeded() {
        if !UserDefaults.standard.bool(forKey: "didOnboardV1") { show() }
    }

    func show() {
        if window == nil {
            let w = OnboardingWindow()
            w.contentView = NSHostingView(rootView: OnboardingView(
                onFinish: { [weak self] in
                    self?.onPreview(.idle)
                    UserDefaults.standard.set(true, forKey: "didOnboardV1")
                    self?.window?.close()
                },
                onPreviewState: onPreview
            ))
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.level = .floating          // stay visible above other apps' windows
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }
}

// MARK: - View

private let fogAccent = Color(hex: 0xD97757)

struct OnboardingView: View {
    var onFinish: () -> Void
    var onPreviewState: (ClaudeState) -> Void = { _ in }
    @State private var step = 0
    @State private var appsAppeared = false
    @AppStorage("autoUpdate") private var autoUpdate = true
    @StateObject private var perms = PermissionsModel()
    @ObservedObject private var model = StatusModel.shared
    private let stepCount = 7
    private let refresh = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x151517), Color(hex: 0x1E1E22)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 22) {
                Group {
                    switch step {
                    case 0: welcome
                    case 1: apps
                    case 2: tryIt
                    case 3: colorStep
                    case 4: permissions
                    case 5: updates
                    default: finish
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)))

                footer
            }
            .padding(28)
            .padding(.top, 8)
        }
        .frame(width: 600, height: 560)
        .onAppear { perms.refresh() }
        .onReceive(refresh) { _ in perms.refresh() }
        .onChange(of: step) { newStep in
            // "Pick your glow" (step 3) auto-lights the border so colors preview live.
            // "Try it" (step 2) starts idle — the user taps a card themselves.
            onPreviewState(newStep == 3 ? .thinking : .idle)
        }
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(spacing: 22) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 100, height: 100)
                .shadow(color: fogAccent.opacity(0.55), radius: 26)
            VStack(spacing: 12) {
                Text("Every second of\nyour limit counts.")
                    .font(.system(size: 30, weight: .bold)).foregroundStyle(.white)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                Text("Don't burn it waiting on your AI — Fog's screen-edge glow\ntaps you the moment it needs you or finishes.")
                    .font(.system(size: 15)).foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("A couple of permissions").font(.system(size: 24, weight: .bold)).foregroundStyle(.white)
                Text("Only the first is needed — the others just unlock extra effects.")
                    .font(.system(size: 13)).foregroundStyle(.white.opacity(0.6))
            }
            permissionRow("bell.badge", "Notifications", "Banner when Claude needs you or finishes.",
                          granted: perms.notifications, optional: false) { perms.requestNotifications() }
            permissionRow("rectangle.dashed.badge.record", "Screen Recording", "Lets the screen shake on the “done” effect.",
                          granted: perms.screenRecording, optional: true) { perms.requestScreenRecording() }
            permissionRow("hand.tap", "Accessibility", "Type your answer back when you click a choice.",
                          granted: perms.accessibility, optional: true) { perms.requestAccessibility() }
            Text("Granting Screen Recording / Accessibility may need a relaunch to take effect.")
                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
        }
    }

    private var updates: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 40, weight: .semibold)).foregroundStyle(fogAccent)
            Text("Stays up to date").font(.system(size: 26, weight: .bold)).foregroundStyle(.white)
            Text("Fog updates itself — new features just show up, no reinstalling.")
                .font(.system(size: 14)).foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Check on launch").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                    Text("Look for new versions each time Fog starts")
                        .font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
                }
                Spacer()
                Toggle("", isOn: $autoUpdate).labelsHidden().toggleStyle(.switch).tint(fogAccent)
            }
            .padding(14)
            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            HStack {
                Text("You're on Fog \(Updater.shared.currentVersion)")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
                Spacer()
                Button("Check now") { Updater.shared.checkForUpdates(userInitiated: true) }
                    .buttonStyle(PrimaryButton(tint: fogAccent, small: true))
            }
            Spacer(minLength: 0)
        }
    }

    private var finish: some View {
        VStack(spacing: 16) {
            CheckBurst()
            Text("You're all set").font(.system(size: 28, weight: .bold)).foregroundStyle(.white)
            Text("Fog lives in your menu bar — click its face to change colors\nor pick a gradient theme. Enjoy the glow. ✦")
                .font(.system(size: 14)).foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Supported apps

    private var apps: some View {
        VStack(alignment: .leading, spacing: 12) {
            header("Works with", "Anything whose hooks can run a command drives Fog.")
            appRow(0, ["com.anthropic.claudefordesktop"], ["Claude"], "terminal.fill",
                   "Claude Code", "any terminal · VS Code · JetBrains")
            appRow(1, [], [], "chevron.left.forwardslash.chevron.right",
                   "Codex CLI", "OpenAI")
            appRow(2, ["com.google.GeminiMacOS"], ["Gemini"], "sparkle",
                   "Gemini CLI", "Google")
            appRow(3, ["com.todesktop.230313mzl4w4u92"], ["Cursor"], "cursorarrow.rays",
                   "Cursor", "built-in agent")
            Text("The Claude / ChatGPT / Gemini desktop & web apps don't expose their status yet, so they're not supported.")
                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .onAppear {
            appsAppeared = false
            // Wait for the step slide to settle, then drop the boxes in top → bottom.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { appsAppeared = true }
        }
        .onDisappear { appsAppeared = false }
    }

    private func appRow(_ index: Int, _ bundleIDs: [String], _ names: [String],
                        _ fallback: String, _ name: String, _ sub: String) -> some View {
        let icon = appIcon(bundleIDs, names)
        return HStack(spacing: 14) {
            Group {
                if let icon {
                    Image(nsImage: icon).resizable().frame(width: 28, height: 28)
                } else {
                    Image(systemName: fallback).font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.8)).frame(width: 28, height: 28)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                Text(sub).font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            Image(systemName: "checkmark.seal.fill").foregroundStyle(.green).font(.system(size: 16))
        }
        .padding(12)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .opacity(appsAppeared ? 1 : 0)
        .offset(y: appsAppeared ? 0 : 16)
        .animation(.spring(response: 0.5, dampingFraction: 0.82).delay(Double(index) * 0.1), value: appsAppeared)
    }

    private func appIcon(_ bundleIDs: [String], _ names: [String]) -> NSImage? {
        let ws = NSWorkspace.shared
        for id in bundleIDs {
            if let u = ws.urlForApplication(withBundleIdentifier: id) { return ws.icon(forFile: u.path) }
        }
        for n in names {
            let p = "/Applications/\(n).app"
            if FileManager.default.fileExists(atPath: p) { return ws.icon(forFile: p) }
        }
        return nil
    }

    // MARK: Color picker

    private var colorStep: some View {
        VStack(spacing: 18) {
            header("Pick your glow", "It's live on your real screen edge — try the swatches.")
            swatchRow("SOLID", model.allSolid)
            swatchRow("GRADIENT", model.allGradient)
            Label("Look at the edges of your screen", systemImage: "eyes")
                .font(.system(size: 12)).foregroundStyle(.white.opacity(0.5)).padding(.top, 4)
            Spacer(minLength: 0)
        }
    }

    private var tryIt: some View {
        VStack(spacing: 20) {
            header("Try it for real", "Tap a card to preview it on your real screen.")
            Spacer(minLength: 0)
            HStack(spacing: 14) {
                tryCard("Thinking", .thinking, "sparkles", "waves on the edge")
                tryCard("Waiting", .waiting, "hand.raised", "holds + sample dialog")
                tryCard("Done", .done, "checkmark.circle", "shine + a chime")
            }
            Group {
                if model.state != .idle {
                    Label("Look at the edges of your screen", systemImage: "eyes")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(fogAccent)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .frame(height: 24)
            Spacer(minLength: 0)
        }
        .animation(.easeInOut(duration: 0.3), value: model.state)
    }

    private func tryCard(_ label: String, _ state: ClaudeState, _ icon: String, _ sub: String) -> some View {
        let on = model.state == state
        return Button {
            onPreviewState(state)   // drives the REAL overlay (border + dialog/pill + sound)
        } label: {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(on ? .white : fogAccent)
                Text(label).font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                Text(sub).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity).frame(height: 150)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(on ? fogAccent.opacity(0.9) : Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(on ? Color.white.opacity(0.55) : Color.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: on ? fogAccent.opacity(0.4) : .clear, radius: 14, y: 4)
        }
        .buttonStyle(.plain)
        .scaleEffect(on ? 1.03 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: on)
    }

    private func swatchRow(_ label: String, _ themes: [Theme]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.45)).kerning(0.5)
            HStack(spacing: 10) {
                ForEach(themes) { t in swatch(t) }
                Spacer()
            }
        }
    }

    private func swatch(_ t: Theme) -> some View {
        let selected = t.id == model.theme.id
        return Circle()
            .fill(themeStyle(t))
            .frame(width: 26, height: 26)
            .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 1))
            .overlay { if selected { Circle().stroke(.white, lineWidth: 2).frame(width: 32, height: 32) } }
            .frame(width: 32, height: 32)
            .contentShape(Circle())
            .onTapGesture { model.selectTheme(t) }
            .help(t.name)
    }

    private func themeStyle(_ t: Theme) -> AnyShapeStyle {
        t.mode == .gradient
            ? AnyShapeStyle(LinearGradient(colors: t.colors, startPoint: .leading, endPoint: .trailing))
            : AnyShapeStyle(t.primary)
    }

    private func header(_ title: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 24, weight: .bold)).foregroundStyle(.white)
            Text(sub).font(.system(size: 13)).foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Pieces

    private func permissionRow(_ icon: String, _ title: String, _ why: String,
                               granted: Bool, optional: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 18)).foregroundStyle(fogAccent).frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                    if optional {
                        Text("OPTIONAL").font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(.white.opacity(0.12), in: Capsule())
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                Text(why).font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
            }
            Spacer()
            if granted {
                Label("On", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(.green)
            } else {
                Button("Grant", action: action)
                    .buttonStyle(PrimaryButton(tint: fogAccent, small: true))
            }
        }
        .padding(14)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var footer: some View {
        HStack(spacing: 8) {
            ForEach(0..<stepCount, id: \.self) { i in
                Circle().fill(i == step ? fogAccent : Color.white.opacity(0.2))
                    .frame(width: 7, height: 7)
            }
            Spacer()
            if step > 0 {
                Button("Back") { withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { step -= 1 } }
                    .buttonStyle(.plain).foregroundStyle(.white.opacity(0.6))
                    .font(.system(size: 13, weight: .medium))
            }
            Button(step == stepCount - 1 ? "Finish" : (step == 0 ? "Get Started" : "Continue")) {
                if step == stepCount - 1 { onFinish() }
                else { withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { step += 1 } }
            }
            .buttonStyle(PrimaryButton(tint: fogAccent, small: false))
            .keyboardShortcut(.defaultAction)
        }
    }
}

private struct PrimaryButton: ButtonStyle {
    var tint: Color
    var small: Bool
    func makeBody(configuration c: Configuration) -> some View {
        c.label
            .font(.system(size: small ? 12 : 14, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, small ? 16 : 26).padding(.vertical, small ? 7 : 11)
            .background(tint.opacity(c.isPressed ? 0.7 : 1), in: Capsule())
            .shadow(color: tint.opacity(0.5), radius: 10, y: 4)
            .scaleEffect(c.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: c.isPressed)
    }
}

private struct CheckBurst: View {
    @State private var on = false
    var body: some View {
        ZStack {
            Circle().fill(Color.green.opacity(0.15)).frame(width: 96, height: 96)
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64)).foregroundStyle(.green)
                .scaleEffect(on ? 1 : 0.4).opacity(on ? 1 : 0)
        }
        .onAppear { withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { on = true } }
    }
}
