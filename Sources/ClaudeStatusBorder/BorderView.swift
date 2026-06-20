import SwiftUI
import AppKit

/// Caches the per-theme conic gradient stops that make the traveling wave pattern.
/// Only the rotation angle changes per frame, so we never rebuild these in the hot loop.
@MainActor
final class ShimmerCache {
    static let shared = ShimmerCache()
    private var cache: [String: [Gradient.Stop]] = [:]

    func stops(for theme: Theme) -> [Gradient.Stop] {
        if let s = cache[theme.id] { return s }
        let s = Self.build(theme)
        cache[theme.id] = s
        return s
    }

    private static func build(_ theme: Theme) -> [Gradient.Stop] {
        let humps = 6.0      // number of wave crests traveling around the border
        let n = 72
        let palette = theme.colors
        var stops: [Gradient.Stop] = []
        for k in 0...n {
            let loc = Double(k) / Double(n)
            let wave = 0.5 + 0.5 * sin(2 * Double.pi * humps * loc)
            let hue = theme.mode == .gradient ? interp(palette, loc) : (palette.first ?? .orange)
            let col = hue.brightened(0.55 * wave)    // crests are brighter (the traveling light)
            let alpha = 0.6 + 0.4 * wave             // continuous glow all the way around the edge
            stops.append(.init(color: col.opacity(alpha), location: loc))
        }
        return stops
    }

    private static func interp(_ colors: [Color], _ t: Double) -> Color {
        guard colors.count > 1 else { return colors.first ?? .orange }
        let ext = colors + [colors[0]]                 // wrap so it loops seamlessly
        let seg = t * Double(ext.count - 1)
        let i = min(ext.count - 2, Int(seg))
        return mix(ext[i], ext[i + 1], seg - Double(i))
    }

    private static func mix(_ a: Color, _ b: Color, _ t: Double) -> Color {
        let na = NSColor(a).usingColorSpace(.sRGB) ?? .black
        let nb = NSColor(b).usingColorSpace(.sRGB) ?? .black
        return Color(.sRGB,
                     red:   na.redComponent   + (nb.redComponent   - na.redComponent)   * t,
                     green: na.greenComponent + (nb.greenComponent - na.greenComponent) * t,
                     blue:  na.blueComponent  + (nb.blueComponent  - na.blueComponent)  * t,
                     opacity: 1)
    }
}

/// The glowing screen-edge border: opacity 100 against the edge, fading to 0 ~16px
/// inward, with crests of light traveling around the perimeter (a wave). Corners are
/// rounded to the real screen-corner radius so the glow hugs the physical curve.
struct BorderView: View {
    @ObservedObject var model: StatusModel

    private let cursorClearRadius: CGFloat = 130  // glow fully clears within this radius of the pointer
    private let cursorFeather: CGFloat = 90       // smooth fade-out zone beyond the clear radius

    var body: some View {
        let show = model.state.showsBorder
        let animates = model.state.animates

        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !animates)) { timeline in
            Canvas { ctx, size in
                guard show else { return }
                draw(into: ctx, size: size, time: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
        .ignoresSafeArea()
        .opacity(show ? 1 : 0)
        .animation(.easeOut(duration: 0.45), value: show)
    }

    private func draw(into ctx: GraphicsContext, size: CGSize, time: Double) {
        let t = time * model.animationSpeed
        let center = CGPoint(x: size.width / 2, y: size.height / 2)

        // Pulse: the glow swells + brightens, then shrinks + dims → a clear blink.
        // Waiting holds at the PEAK (widest + brightest) to grab attention.
        let p = (model.state == .waiting) ? 1.0 : (0.5 + 0.5 * sin(t * 2.6))
        let opacity = 0.30 + 0.70 * p
        let widthScale = 0.55 + 0.45 * p
        let angle = Angle(radians: t * 1.0)               // travels the wave around the edge

        let stops = ShimmerCache.shared.stops(for: model.theme)
        let shading = GraphicsContext.Shading.conicGradient(Gradient(stops: stops), center: center, angle: angle)
        let radius = model.screenCornerRadius
        let rect = CGRect(origin: .zero, size: size)
        let path = Path(roundedRect: rect, cornerRadius: radius)

        // Draw both glow layers into one layer so we can punch a hole around the cursor.
        ctx.drawLayer { outer in
            // Wide, diffuse halo — a single stroke + blur (no banding).
            outer.drawLayer { l in
                l.addFilter(.blur(radius: 30 * widthScale))
                var c = l
                c.opacity = opacity * 0.9
                c.stroke(path, with: shading, lineWidth: 64 * widthScale)
            }
            // Brighter, tighter core so the waves stay legible.
            outer.drawLayer { l in
                l.addFilter(.blur(radius: 9 * widthScale))
                var c = l
                c.opacity = opacity
                c.stroke(path, with: shading, lineWidth: 24 * widthScale)
            }
            // Erase the glow near the pointer so it never hides clickable content.
            let cur = model.cursorLocation
            if cur.x > -500 {
                let r = cursorClearRadius + cursorFeather
                var e = outer
                e.blendMode = .destinationOut
                let grad = Gradient(stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: cursorClearRadius / r),
                    .init(color: .black.opacity(0.5), location: (cursorClearRadius + cursorFeather * 0.45) / r),
                    .init(color: .clear, location: 1),
                ])
                e.fill(
                    Path(ellipseIn: CGRect(x: cur.x - r, y: cur.y - r, width: 2 * r, height: 2 * r)),
                    with: .radialGradient(grad, center: cur, startRadius: 0, endRadius: r)
                )
            }
        }
    }
}

/// One-shot "new result" sweep: a bright shine travels from the bottom-left toward
/// the bottom-right across the whole screen, with a soft full-screen tint flash.
/// The Done effect: a screenshot of the screen shakes briefly (so the content behind
/// appears to vibrate), a full-screen "new" glow flashes, and a bright gloss streak
/// swipes left → right like a shine.
struct DoneOverlay: View {
    let color: Color
    let image: CGImage?

    @State private var startTime = Date()
    @State private var swipe: CGFloat = 0
    @State private var tint: Double = 0
    @State private var imageOpacity: Double = 1

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                // Snapshot that shakes, then fades to reveal the live (settled) content.
                if let image {
                    TimelineView(.animation) { tl in
                        let e = tl.date.timeIntervalSince(startTime)
                        let (dx, dy) = shake(e)
                        Image(decorative: image, scale: NSScreen.main?.backingScaleFactor ?? 2)
                            .resizable()
                            .scaledToFill()
                            .frame(width: w, height: h)
                            .offset(x: dx, y: dy)
                            .opacity(imageOpacity)
                    }
                }

                // Full-screen "new" glow flash.
                color.opacity(0.18 * tint)

                // Bright gloss streak swiping left → right.
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                .clear,
                                color.brightened(0.6).opacity(0.0),
                                color.brightened(0.7).opacity(0.9),
                                Color.white.opacity(0.95),
                                color.brightened(0.7).opacity(0.9),
                                color.brightened(0.6).opacity(0.0),
                                .clear,
                            ],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(width: w * 0.34)
                    .blur(radius: 26)
                    .rotationEffect(.degrees(18))
                    .offset(x: -w * 0.85 + swipe * (w * 1.7))
            }
            .ignoresSafeArea()
            .onAppear {
                startTime = Date()
                withAnimation(.easeIn(duration: 0.12)) { tint = 1 }
                withAnimation(.easeInOut(duration: 0.85)) { swipe = 1 }
                withAnimation(.easeOut(duration: 0.5).delay(0.4)) { tint = 0 }
                withAnimation(.easeOut(duration: 0.45).delay(0.5)) { imageOpacity = 0 }
            }
        }
        .ignoresSafeArea()
    }

    /// Decaying high-frequency jitter for the screen-shake.
    private func shake(_ e: TimeInterval) -> (CGFloat, CGFloat) {
        let duration = 0.5
        guard e < duration else { return (0, 0) }
        let decay = 1 - (e / duration)
        let amp = 18.0 * decay
        return (CGFloat(sin(e * 58) * amp), CGFloat(cos(e * 47) * amp * 0.7))
    }
}
