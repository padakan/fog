import AppKit

// Renders the DMG window background (600×400) → Resources/dmg-background.png
let W = 600, H = 400
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H,
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                           isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let orange = NSColor(srgbRed: 0xD9/255, green: 0x77/255, blue: 0x57/255, alpha: 1)

// Soft warm background gradient.
NSGradient(starting: NSColor(white: 1, alpha: 1),
           ending: NSColor(srgbRed: 0xF6/255, green: 0xEF/255, blue: 0xEA/255, alpha: 1))!
    .draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -90)

func draw(_ s: String, _ size: CGFloat, _ weight: NSFont.Weight, _ color: NSColor, centerY: CGFloat) {
    let p = NSMutableParagraphStyle(); p.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color, .paragraphStyle: p,
    ]
    let str = NSAttributedString(string: s, attributes: attrs)
    let h = str.size().height
    str.draw(in: NSRect(x: 0, y: centerY - h / 2, width: CGFloat(W), height: h))
}

// Titles (AppKit origin = bottom-left).
draw("Install Fog", 27, .bold, NSColor(white: 0.16, alpha: 1), centerY: 348)
draw("Drag Fog into the Applications folder", 13, .regular, NSColor(white: 0.5, alpha: 1), centerY: 320)

// Arrow between the two icons (icons sit at window-y 200 → AppKit y 200).
let y: CGFloat = 200
let shaft = NSBezierPath()
shaft.lineWidth = 9
shaft.lineCapStyle = .round
shaft.move(to: NSPoint(x: 250, y: y))
shaft.line(to: NSPoint(x: 343, y: y))
orange.setStroke(); shaft.stroke()
let head = NSBezierPath()
head.lineWidth = 9; head.lineCapStyle = .round; head.lineJoinStyle = .round
head.move(to: NSPoint(x: 336, y: y + 14))
head.line(to: NSPoint(x: 358, y: y))
head.line(to: NSPoint(x: 336, y: y - 14))
head.stroke()

// First-launch hint baked into the background (no extra icon needed).
draw("First launch: right-click Fog → Open", 11, .regular, NSColor(white: 0.62, alpha: 1), centerY: 44)

NSGraphicsContext.restoreGraphicsState()
let out = URL(fileURLWithPath: "Resources/dmg-background.png")
try! rep.representation(using: .png, properties: [:])!.write(to: out)
print("✓ wrote \(out.path)")
