import AppKit

/// Plays bundled sound effects (Contents/Resources/*.mp3).
@MainActor
final class SoundPlayer {
    static let shared = SoundPlayer()
    private var cache: [String: NSSound] = [:]

    func play(_ name: String) {
        let sound: NSSound
        if let s = cache[name] {
            sound = s
        } else if let url = Bundle.main.url(forResource: name, withExtension: "mp3"),
                  let s = NSSound(contentsOf: url, byReference: false) {
            cache[name] = s
            sound = s
        } else {
            return
        }
        sound.stop()        // allow rapid re-triggering
        sound.play()
    }
}

/// Grabs the current screen content for the Done shake effect.
/// Needs Screen Recording permission; returns nil (graceful) until granted.
enum ScreenCapture {
    /// Capture everything *below* our overlay window so our own glow isn't included.
    /// Returns nil (so the shake is skipped, leaving live content visible) unless
    /// Screen Recording permission is granted — otherwise macOS hands back a
    /// desktop-only image that looks like the windows vanished.
    static func grabBelow(window: Int) -> CGImage? {
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()      // prompt once for next time
            return nil
        }
        if window > 0,
           let img = CGWindowListCreateImage(.infinite, .optionOnScreenBelowWindow,
                                             CGWindowID(window), [.bestResolution]) {
            return img
        }
        guard let screen = NSScreen.main,
              let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else { return nil }
        return CGDisplayCreateImage(CGDirectDisplayID(num.uint32Value))
    }
}
