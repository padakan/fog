import SwiftUI

/// Liquid-glass-ish button (approximated with material on macOS 15).
struct GlassButton: ButtonStyle {
    var tint: Color
    var prominent: Bool

    func makeBody(configuration c: Configuration) -> some View {
        c.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(
                ZStack {
                    Capsule().fill(.ultraThinMaterial)
                    Capsule().fill(
                        prominent
                            ? tint.opacity(c.isPressed ? 0.6 : 0.92)
                            : Color.white.opacity(c.isPressed ? 0.16 : 0.07)
                    )
                }
            )
            .overlay(Capsule().stroke(.white.opacity(0.18), lineWidth: 1))
            .shadow(color: .black.opacity(prominent ? 0.25 : 0), radius: 8, y: 3)
            .contentShape(Capsule())
            .scaleEffect(c.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: c.isPressed)
    }
}

private struct GlassCard<Content: View>: View {
    var tint: Color
    var corner: CGFloat = 22
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(.white.opacity(0.18), lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(tint.opacity(0.30), lineWidth: 1.5)
                    .blur(radius: 2.5)
            )
            // Soft themed glow instead of a gray drop shadow.
            .shadow(color: tint.opacity(0.30), radius: 18, y: 6)
    }
}

/// Drops in from the top of the screen when Claude is waiting.
struct WaitingModalView: View {
    let question: String
    let options: [String]
    let tint: Color
    var onOption: (Int) -> Void
    var onFocus: () -> Void
    var onDismiss: () -> Void

    @State private var appear = false

    var body: some View {
        GlassCard(tint: tint) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "hand.raised.fill")
                        .foregroundStyle(tint)
                    Text("Claude is waiting")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }

                Text(question)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                if options.isEmpty {
                    HStack(spacing: 10) {
                        Button("Go to Claude", action: onFocus)
                            .buttonStyle(GlassButton(tint: tint, prominent: true))
                        Button("Dismiss", action: onDismiss)
                            .buttonStyle(GlassButton(tint: .gray, prominent: false))
                    }
                } else {
                    VStack(spacing: 8) {
                        ForEach(Array(options.enumerated()), id: \.offset) { i, opt in
                            Button { onOption(i) } label: {
                                HStack(spacing: 10) {
                                    Text("\(i + 1)")
                                        .font(.system(size: 11, weight: .heavy))
                                        .foregroundStyle(tint)
                                        .frame(width: 16)
                                    Text(opt).foregroundStyle(.primary)
                                    Spacer(minLength: 0)
                                }
                            }
                            .buttonStyle(GlassButton(tint: tint, prominent: false))
                        }
                    }
                }
            }
            .padding(18)
            .frame(width: 420)
        }
        .offset(y: appear ? 0 : -28)
        .opacity(appear ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) { appear = true }
        }
    }
}

/// Small glass pill that appears after the Done sweep.
struct DonePillView: View {
    let tint: Color
    var onOpen: () -> Void
    var onDismiss: () -> Void

    @State private var appear = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
            Text("Done")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
            Button(action: onOpen) {
                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 13, weight: .bold))
            }
            .buttonStyle(GlassButton(tint: tint, prominent: true))
            .help("Open Claude")
            Button(action: onDismiss) {
                Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.18), lineWidth: 1))
        .overlay(Capsule().stroke(tint.opacity(0.3), lineWidth: 1.5).blur(radius: 2))
        .shadow(color: tint.opacity(0.30), radius: 18, y: 6)
        .offset(y: appear ? 0 : -22)
        .opacity(appear ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { appear = true }
        }
    }
}
