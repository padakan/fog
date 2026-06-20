import SwiftUI
import AppKit

/// Popover content: pick a border color as a colored circle, add your own (up to 8
/// per category), and a footer credit link.
struct ThemePicker: View {
    @ObservedObject var model: StatusModel
    var onPreview: (ClaudeState) -> Void = { _ in }
    var version: String = ""
    var onCheckUpdates: () -> Void = {}

    @State private var addingSolid = false
    @State private var addingGradient = false
    @State private var newSolid = Color(hex: 0xD97757)
    @State private var newGradA = Color(hex: 0x4285F4)
    @State private var newGradB = Color(hex: 0xD96570)

    private let columns = Array(repeating: GridItem(.fixed(34), spacing: 6), count: 5)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: model.state.symbol).foregroundStyle(model.theme.primary)
                Text("Claude: \(model.state.title)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            sectionHeader("Solid")
            grid(themes: model.allSolid,
                 canAdd: model.allSolid.count < StatusModel.maxPerCategory,
                 adding: $addingSolid)
            if addingSolid {
                HStack(spacing: 8) {
                    ColorPicker("", selection: $newSolid, supportsOpacity: false).labelsHidden()
                    Button("Add") { model.addCustomSolid(newSolid); addingSolid = false }
                        .controlSize(.small)
                    Spacer()
                }
            }

            Divider()

            sectionHeader("Gradient")
            grid(themes: model.allGradient,
                 canAdd: model.allGradient.count < StatusModel.maxPerCategory,
                 adding: $addingGradient)
            if addingGradient {
                HStack(spacing: 6) {
                    ColorPicker("", selection: $newGradA, supportsOpacity: false).labelsHidden()
                    Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.secondary)
                    ColorPicker("", selection: $newGradB, supportsOpacity: false).labelsHidden()
                    Button("Add") { model.addCustomGradient([newGradA, newGradB]); addingGradient = false }
                        .controlSize(.small)
                    Spacer()
                }
            }

            Divider()

            sectionHeader("Preview")
            previewControls

            Divider()

            HStack(spacing: 6) {
                Text("Fog \(version)").font(.system(size: 11)).foregroundStyle(.secondary)
                Button("Check for updates", action: onCheckUpdates)
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.blue)
                Text("·").foregroundStyle(.secondary)
                Button("Setup") { OnboardingController.shared.show() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.blue)
                Spacer()
            }

            footer
        }
        .padding(16)
        .frame(width: 280)
    }

    private let previewStates: [ClaudeState] = [.thinking, .working, .waiting, .done, .idle]

    private var previewControls: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
            ForEach(previewStates, id: \.self) { s in
                Button { onPreview(s) } label: {
                    HStack(spacing: 5) {
                        Image(systemName: s.symbol).font(.system(size: 10))
                        Text(shortLabel(s)).font(.system(size: 11, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(s == model.state ? model.theme.primary : .secondary)
            }
        }
    }

    private func shortLabel(_ s: ClaudeState) -> String {
        switch s {
        case .idle: return "Idle"
        case .thinking: return "Thinking"
        case .working: return "Working"
        case .waiting: return "Waiting"
        case .done: return "Done"
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.secondary)
            .kerning(0.5)
    }

    private func grid(themes: [Theme], canAdd: Bool, adding: Binding<Bool>) -> some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(themes) { t in
                swatch(t)
            }
            if canAdd {
                Button { adding.wrappedValue.toggle() } label: {
                    ZStack {
                        Circle().fill(Color.white.opacity(0.06)).frame(width: 28, height: 28)
                        Circle().strokeBorder(.secondary.opacity(0.5),
                                              style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                            .frame(width: 28, height: 28)
                        Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func swatch(_ t: Theme) -> some View {
        let selected = t.id == model.theme.id
        return ZStack {
            Circle()
                .fill(fill(for: t))
                .frame(width: 28, height: 28)
                .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 1))
            if selected {
                Circle().stroke(Color.primary, lineWidth: 2)
                    .frame(width: 34, height: 34)
            }
        }
        .frame(width: 34, height: 34)
        .overlay(alignment: .topTrailing) {
            if model.isCustom(t) {
                Button { model.removeTheme(t) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.white, .black.opacity(0.6))
                }
                .buttonStyle(.plain)
                .offset(x: 3, y: -3)
            }
        }
        .contentShape(Circle())
        .onTapGesture { model.selectTheme(t); onPreview(.thinking) }   // preview the color ~5s
        .help(t.name)
    }

    private func fill(for t: Theme) -> AnyShapeStyle {
        if t.mode == .gradient {
            return AnyShapeStyle(
                LinearGradient(colors: t.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            )
        }
        return AnyShapeStyle(t.primary)
    }

    private var footer: some View {
        HStack(spacing: 0) {
            Text("made with ")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            Image(systemName: "heart.fill")
                .font(.system(size: 9)).foregroundStyle(.pink)
            Text(" by ")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            Button("@padagot") {
                if let url = URL(string: "https://instagram.com/padagot") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.blue)
            Spacer()
            Button { model.setSound(!model.soundEnabled) } label: {
                Image(systemName: model.soundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(model.soundEnabled ? Color.primary : .secondary)
            .help(model.soundEnabled ? "Mute sounds" : "Enable sounds")
            Button("Quit") { NSApp.terminate(nil) }
                .controlSize(.small)
        }
    }
}
