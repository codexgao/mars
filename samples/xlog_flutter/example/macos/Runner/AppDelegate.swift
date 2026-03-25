import Cocoa
import FlutterMacOS
import xlog_flutter

@main
class AppDelegate: FlutterAppDelegate {

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)

    // MARK: - xlog native ObjC wrapper usage example
    let appSupport = FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask
    ).first!
    let logDir = appSupport.appendingPathComponent("xlog_native").path

    let config = XLogConfig()
    config.logdir      = logDir
    config.nameprefix  = "native_demo"
    config.mode        = .async
    config.compressMode = .zlib

    if let log = XLogManager.open(with: config, level: .debug) {
      log.info("AppDelegate", msg: "xlog native ObjC wrapper initialized (macOS)")
      log.debug("AppDelegate", msg: "application did finish launching")
      log.warn("AppDelegate", msg: "this is a warning from native wrapper")

      log.flush(false)
      XLogManager.releaseInstance(withName: "native_demo")
    }
    // END xlog example
  }
}
