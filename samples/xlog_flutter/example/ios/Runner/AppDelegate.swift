import Flutter
import UIKit
import xlog_flutter

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // MARK: - xlog native ObjC wrapper usage example
    let docsDir = NSSearchPathForDirectoriesInDomains(
        .documentDirectory, .userDomainMask, true
    ).first!
    let logDir = (docsDir as NSString).appendingPathComponent("xlog_native")

    let config = XLogConfig()
    config.logdir      = logDir
    config.nameprefix  = "native_demo"
    config.mode        = .async
    config.compressMode = .zlib

    if let log = XLogManager.open(with: config, level: .debug) {
      log.info("AppDelegate", msg: "xlog native ObjC wrapper initialized")
      log.debug("AppDelegate", msg: "application did finish launching")
      log.warn("AppDelegate", msg: "this is a warning from native wrapper")

      // Flush and release when done
      log.flush(false)
      XLogManager.releaseInstance(withName: "native_demo")
    }
    // END xlog example

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
