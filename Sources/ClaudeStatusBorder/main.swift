import AppKit

// Top-level code runs on the main thread; assert main-actor isolation so we can
// build the (main-actor) delegate.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
