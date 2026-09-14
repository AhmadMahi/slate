import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Standard native window chrome: the real traffic lights and the window
    // title, and the normal full-screen behaviour — the green button enters
    // full screen and the title bar reveals on hover there, as in any Mac app.
    // (The drawn-lights experiment is gone; macOS owns the title bar again.)
    self.collectionBehavior.insert(.fullScreenPrimary)

    super.awakeFromNib()
  }
}
