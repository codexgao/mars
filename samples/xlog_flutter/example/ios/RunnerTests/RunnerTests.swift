import Flutter
import UIKit
import XCTest
import xlog_flutter

class XlogNativeIOSTests: XCTestCase {

    // MARK: - Helpers

    /// Returns a temporary directory path unique to each test invocation.
    private func tempLogDir(name: String) -> String {
        let base = NSTemporaryDirectory()
        let dir = (base as NSString).appendingPathComponent("xlog_test_\(name)_\(arc4random())")
        try? FileManager.default.createDirectory(atPath: dir,
                                                  withIntermediateDirectories: true)
        return dir
    }

    /// Creates a minimal valid XLogConfig.
    private func makeConfig(logdir: String, nameprefix: String,
                            compressMode: XLogCompressMode = .zlib) -> XLogConfig {
        let cfg = XLogConfig()
        cfg.logdir = logdir
        cfg.nameprefix = nameprefix
        cfg.compressMode = compressMode
        cfg.compressLevel = 0
        return cfg
    }

    // MARK: - setUp / tearDown

    override func tearDown() {
        super.tearDown()
        // Flush everything so the engine is in a clean state between tests.
        XLogManager.flushAll()
    }

    // MARK: - Test 1: openWithConfig returns a valid instance

    func testOpenReturnsValidInstance() {
        let dir = tempLogDir(name: "open")
        let cfg = makeConfig(logdir: dir, nameprefix: "t1")
        let instance = XLogManager.open(with: cfg, level: .debug)
        XCTAssertNotNil(instance, "openWithConfig should return a non-nil instance")
        XCTAssertTrue(instance?.isValid ?? false, "Returned instance should be valid")
        XLogManager.releaseInstance(withName: "t1")
    }

    // MARK: - Test 2: hasInstanceWithName returns true after open

    func testHasInstanceAfterOpen() {
        let dir = tempLogDir(name: "has")
        let cfg = makeConfig(logdir: dir, nameprefix: "t2")
        _ = XLogManager.open(with: cfg, level: .info)
        XCTAssertTrue(XLogManager.hasInstance(withName: "t2"),
                      "hasInstanceWithName should return true after open")
        XLogManager.releaseInstance(withName: "t2")
    }

    // MARK: - Test 3: getInstanceByName returns the same instance as open

    func testGetInstanceByNameReturnsSameInstance() {
        let dir = tempLogDir(name: "get")
        let cfg = makeConfig(logdir: dir, nameprefix: "t3")
        let opened = XLogManager.open(with: cfg, level: .info)
        let fetched = XLogManager.getInstanceByName("t3")
        XCTAssertNotNil(fetched, "getInstanceByName should return a non-nil instance")
        XCTAssertTrue(fetched?.isValid ?? false,
                      "Instance retrieved by name should be valid")
        // Both handles should refer to the same underlying xlog instance.
        XCTAssertEqual(opened?._xlog_handle(), fetched?._xlog_handle(),
                       "Opened and fetched instances should share the same handle")
        XLogManager.releaseInstance(withName: "t3")
    }

    // MARK: - Test 4: releaseInstanceWithName → hasInstance returns false

    func testReleaseInstanceRemovesIt() {
        let dir = tempLogDir(name: "release")
        let cfg = makeConfig(logdir: dir, nameprefix: "t4")
        _ = XLogManager.open(with: cfg, level: .info)
        XCTAssertTrue(XLogManager.hasInstance(withName: "t4"))
        XLogManager.releaseInstance(withName: "t4")
        XCTAssertFalse(XLogManager.hasInstance(withName: "t4"),
                       "hasInstanceWithName should return false after releaseInstanceWithName")
    }

    // MARK: - Test 5: Write all 6 log levels without crash

    func testWriteAllLogLevelsDoesNotCrash() {
        let dir = tempLogDir(name: "levels")
        let cfg = makeConfig(logdir: dir, nameprefix: "t5")
        guard let inst = XLogManager.open(with: cfg, level: .verbose) else {
            XCTFail("Failed to create xlog instance")
            return
        }
        // None of these calls should crash.
        inst.verbose("tag", msg: "verbose message")
        inst.debug("tag", msg: "debug message")
        inst.info("tag", msg: "info message")
        inst.warn("tag", msg: "warn message")
        inst.error("tag", msg: "error message")
        inst.fatal("tag", msg: "fatal message")
        XLogManager.releaseInstance(withName: "t5")
    }

    // MARK: - Test 6: level get/set is consistent

    func testLevelGetSetIsConsistent() {
        let dir = tempLogDir(name: "level")
        let cfg = makeConfig(logdir: dir, nameprefix: "t6")
        guard let inst = XLogManager.open(with: cfg, level: .info) else {
            XCTFail("Failed to create xlog instance")
            return
        }
        XCTAssertEqual(inst.level, .info, "Initial level should match open parameter")

        inst.level = .warn
        XCTAssertEqual(inst.level, .warn, "Level should reflect the newly set value")

        inst.level = .verbose
        XCTAssertEqual(inst.level, .verbose, "Level should reflect the newly set value")
        XLogManager.releaseInstance(withName: "t6")
    }

    // MARK: - Test 7: flush(sync:true) → logPath is non-empty

    func testFlushSyncProducesLogPath() {
        let dir = tempLogDir(name: "flush")
        let cfg = makeConfig(logdir: dir, nameprefix: "t7")
        guard let inst = XLogManager.open(with: cfg, level: .debug) else {
            XCTFail("Failed to create xlog instance")
            return
        }
        inst.info("tag", msg: "flush test message")
        inst.flush(true)
        let path = inst.logPath
        XCTAssertNotNil(path, "logPath should be non-nil after a sync flush")
        XCTAssertFalse(path?.isEmpty ?? true, "logPath should not be empty after a sync flush")
        XLogManager.releaseInstance(withName: "t7")
    }

    // MARK: - Test 8: Config with compressMode .zstd → no crash

    func testZstdCompressModeDoesNotCrash() {
        let dir = tempLogDir(name: "zstd")
        let cfg = makeConfig(logdir: dir, nameprefix: "t8", compressMode: .zstd)
        cfg.compressLevel = 3
        guard let inst = XLogManager.open(with: cfg, level: .debug) else {
            XCTFail("Failed to create xlog instance with zstd compress mode")
            return
        }
        inst.info("tag", msg: "zstd compress test")
        inst.flush(true)
        XLogManager.releaseInstance(withName: "t8")
    }

    // MARK: - Test 9: destroyInstance invalidates the object

    func testDestroyInstanceInvalidatesIt() {
        let dir = tempLogDir(name: "destroy")
        let cfg = makeConfig(logdir: dir, nameprefix: "t9")
        guard let inst = XLogManager.open(with: cfg, level: .debug) else {
            XCTFail("Failed to create xlog instance")
            return
        }
        XCTAssertTrue(inst.isValid)
        XLogManager.destroyInstance(inst)
        XCTAssertFalse(inst.isValid, "Instance should be invalid after destroyInstance")
    }

    // MARK: - Test 10: isEnabledFor reflects current level

    func testIsEnabledForReflectsLevel() {
        let dir = tempLogDir(name: "enabled")
        let cfg = makeConfig(logdir: dir, nameprefix: "t10")
        guard let inst = XLogManager.open(with: cfg, level: .warn) else {
            XCTFail("Failed to create xlog instance")
            return
        }
        XCTAssertFalse(inst.isEnabled(for: .debug),
                       "DEBUG should not be enabled when level is WARN")
        XCTAssertFalse(inst.isEnabled(for: .info),
                       "INFO should not be enabled when level is WARN")
        XCTAssertTrue(inst.isEnabled(for: .warn),
                      "WARN should be enabled when level is WARN")
        XCTAssertTrue(inst.isEnabled(for: .error),
                      "ERROR should be enabled when level is WARN")
        XLogManager.releaseInstance(withName: "t10")
    }

    // MARK: - Test 11: appenderMode setter does not crash

    func testAppenderModeSetterDoesNotCrash() {
        let dir = tempLogDir(name: "appmode")
        let cfg = makeConfig(logdir: dir, nameprefix: "t11")
        guard let inst = XLogManager.open(with: cfg, level: .debug) else {
            XCTFail("Failed to create xlog instance")
            return
        }
        inst.appenderMode = .sync
        inst.appenderMode = .async
        XLogManager.releaseInstance(withName: "t11")
    }

    // MARK: - Test 12: consoleLogOpen setter does not crash

    func testConsoleLogOpenSetterDoesNotCrash() {
        let dir = tempLogDir(name: "console")
        let cfg = makeConfig(logdir: dir, nameprefix: "t12")
        guard let inst = XLogManager.open(with: cfg, level: .debug) else {
            XCTFail("Failed to create xlog instance")
            return
        }
        inst.consoleLogOpen = true
        inst.consoleLogOpen = false
        XLogManager.releaseInstance(withName: "t12")
    }

    // MARK: - Test 13: write(level:tag:msg:) convenience method

    func testWriteConvenienceMethod() {
        let dir = tempLogDir(name: "write")
        let cfg = makeConfig(logdir: dir, nameprefix: "t13")
        guard let inst = XLogManager.open(with: cfg, level: .verbose) else {
            XCTFail("Failed to create xlog instance")
            return
        }
        for level in [XLogLevel.verbose, .debug, .info, .warn, .error, .fatal] {
            inst.write(level, tag: "write_test", msg: "msg at level \(level.rawValue)")
        }
        inst.flush(true)
        XLogManager.releaseInstance(withName: "t13")
    }

    // MARK: - Performance Test: write 100 logs

    func testPerformanceWrite100Logs() {
        let dir = tempLogDir(name: "perf")
        let cfg = makeConfig(logdir: dir, nameprefix: "t_perf")
        guard let inst = XLogManager.open(with: cfg, level: .verbose) else {
            XCTFail("Failed to create xlog instance")
            return
        }
        measure {
            for i in 0..<100 {
                inst.info("perf_tag", msg: "performance log message \(i)")
            }
            inst.flush(true)
        }
        XLogManager.releaseInstance(withName: "t_perf")
    }
}
