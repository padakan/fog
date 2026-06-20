import SwiftUI

/// The high-level state Claude Code is in.
enum ClaudeState: String, Codable {
    case idle       // nothing happening / session ended
    case thinking   // prompt submitted, model reasoning
    case working    // a tool is running
    case waiting    // needs the user (permission / answer)
    case done       // finished a response

    var title: String {
        switch self {
        case .idle:     return "Idle"
        case .thinking: return "Thinking…"
        case .working:  return "Working"
        case .waiting:  return "Waiting for you"
        case .done:     return "Done"
        }
    }

    var symbol: String {
        switch self {
        case .idle:     return "moon.zzz"
        case .thinking: return "sparkles"
        case .working:  return "gearshape.2"
        case .waiting:  return "hand.raised"
        case .done:     return "checkmark.circle"
        }
    }

    /// Border is drawn for these states (waiting is drawn but frozen).
    var showsBorder: Bool {
        self == .thinking || self == .working || self == .waiting
    }

    /// Border animates only while thinking/working. Waiting holds still.
    var animates: Bool {
        self == .thinking || self == .working
    }
}

/// Payload sent by the hook script over HTTP.
struct StatusUpdate: Codable {
    var state: ClaudeState
    var detail: String? = nil
    var question: String? = nil
    var options: [String]? = nil
    var notify: Bool? = nil
    var notifyTitle: String? = nil
    var notifyBody: String? = nil
}

@MainActor
final class StatusModel: ObservableObject {
    static let shared = StatusModel()

    static let maxPerCategory = 8

    @Published var state: ClaudeState = .idle
    @Published var detail: String = ""
    @Published var question: String = ""
    @Published var options: [String] = []
    @Published var theme: Theme
    @Published var doneTick: Int = 0   // bumps each time we enter `done`, re-triggers the sweep
    @Published var screenCornerRadius: CGFloat = 0
    @Published var cursorLocation: CGPoint = CGPoint(x: -1000, y: -1000)  // in overlay view coords
    @Published var doneShakeImage: CGImage?   // screenshot shaken during the Done effect

    @Published var customSolid: [Theme] = []
    @Published var customGradient: [Theme] = []
    @Published var soundEnabled: Bool = (UserDefaults.standard.object(forKey: "soundEnabled") as? Bool) ?? true

    private var idleTask: Task<Void, Never>?

    private init() {
        var cs: [Theme] = []
        var cg: [Theme] = []
        if let data = UserDefaults.standard.data(forKey: "customThemes"),
           let arr = try? JSONDecoder().decode([StoredTheme].self, from: data) {
            cs = arr.filter { $0.mode == "solid" }.map { $0.theme }
            cg = arr.filter { $0.mode == "gradient" }.map { $0.theme }
        }
        customSolid = cs
        customGradient = cg
        let id = UserDefaults.standard.string(forKey: "themeID")
        theme = (Themes.all + cs + cg).first { $0.id == id } ?? Themes.default
    }

    var allSolid: [Theme] { Themes.solid + customSolid }
    var allGradient: [Theme] { Themes.gradient + customGradient }

    func isCustom(_ t: Theme) -> Bool { t.id.hasPrefix("custom.") }

    func apply(_ update: StatusUpdate) {
        idleTask?.cancel(); idleTask = nil

        state = update.state
        detail = update.detail ?? ""

        if update.state == .waiting {
            question = update.question ?? update.detail ?? "Claude needs your input"
            options = update.options ?? []
        }

        if update.state == .done {
            doneTick &+= 1
            idleTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 12_000_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run { self?.goIdle() }
            }
        }
    }

    func goIdle() {
        idleTask?.cancel(); idleTask = nil
        state = .idle
        detail = ""
        doneShakeImage = nil
    }

    /// Auto-return to idle after a delay — used for menu-bar previews only.
    func startPreviewIdle(seconds: Double) {
        idleTask?.cancel()
        idleTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.goIdle() }
        }
    }

    func selectTheme(_ t: Theme) {
        theme = t
        UserDefaults.standard.set(t.id, forKey: "themeID")
    }

    func setSound(_ on: Bool) {
        soundEnabled = on
        UserDefaults.standard.set(on, forKey: "soundEnabled")
    }

    func addCustomSolid(_ color: Color) {
        guard allSolid.count < Self.maxPerCategory else { return }
        let t = Theme(id: "custom.solid.\(UUID().uuidString.prefix(8))",
                      name: "Custom", mode: .solid, colors: [color])
        customSolid.append(t)
        saveCustoms()
        selectTheme(t)
    }

    func addCustomGradient(_ colors: [Color]) {
        guard allGradient.count < Self.maxPerCategory, colors.count >= 2 else { return }
        let t = Theme(id: "custom.grad.\(UUID().uuidString.prefix(8))",
                      name: "Custom", mode: .gradient, colors: colors)
        customGradient.append(t)
        saveCustoms()
        selectTheme(t)
    }

    func removeTheme(_ t: Theme) {
        customSolid.removeAll { $0.id == t.id }
        customGradient.removeAll { $0.id == t.id }
        saveCustoms()
        if theme.id == t.id { selectTheme(Themes.default) }
    }

    private func saveCustoms() {
        let arr = (customSolid + customGradient).map { StoredTheme($0) }
        if let data = try? JSONEncoder().encode(arr) {
            UserDefaults.standard.set(data, forKey: "customThemes")
        }
    }

    /// Animation speed multiplier: working shimmer runs 2× thinking.
    var animationSpeed: Double {
        state == .working ? 2.0 : 1.0
    }
}
