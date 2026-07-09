import AppKit

// Menu-bar only app (no Dock icon). We drive NSApplication manually because this
// is a SwiftPM executable rather than an Xcode app target.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
