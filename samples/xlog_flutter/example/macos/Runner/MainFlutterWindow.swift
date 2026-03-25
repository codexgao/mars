import Cocoa
import FlutterMacOS
import xlog_flutter

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()

    // MARK: - xlog native ObjC wrapper usage example
    let appSupport = FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask
    ).first!
    let logDir = appSupport.appendingPathComponent("xlog_native").path

    let config = XLogConfig()
    config.logdir       = logDir
    config.nameprefix   = "native_demo"
    config.mode         = .async
    config.compressMode = .zlib

    if let log = XLogManager.open(with: config, level: .debug) {
      log.info("MainFlutterWindow", msg: "xlog native ObjC wrapper initialized (macOS)")
      log.debug("MainFlutterWindow", msg: "awakeFromNib — window ready")
      log.warn("MainFlutterWindow", msg: "this is a warning from native wrapper")

      log.flush(false)
      XLogManager.releaseInstance(withName: "native_demo")
    }
    // END xlog example
  }
}
