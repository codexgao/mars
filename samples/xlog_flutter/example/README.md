# xlog_flutter Example & Tests

This directory contains the example app and integration tests for the `xlog_flutter` plugin.

## Running Tests

### Flutter Integration Tests (Recommended)

Integration tests run on a real device or simulator and cover the full Dart API.

```bash
cd samples/xlog_flutter/example

# macOS
fvm flutter test integration_test/ -d macos

# iOS Simulator (pick a simulator name from `xcrun simctl list`)
fvm flutter test integration_test/ -d "iPhone 16"

# Android Emulator (start an emulator first, then)
fvm flutter test integration_test/ -d emulator-5554
```

**44 test cases** across 5 groups:

| Group | File | Cases |
|-------|------|-------|
| Instance Lifecycle | `xlog_open_cases.dart` | 8 |
| Write Operations | `xlog_write_cases.dart` | 18 |
| Level Control | `xlog_level_cases.dart` | 7 |
| Control Methods | `xlog_control_cases.dart` | 7 |
| Multi-Instance | `xlog_multi_instance_cases.dart` | 5 |

> **Note:** Sub-test modules are named `*_cases.dart` (not `*_test.dart`) so that
> Flutter's test runner only discovers `xlog_all_test.dart` as the single entry point.
> This ensures all tests run in one app process, avoiding xlog file-lock conflicts.

### macOS Native Tests (XCTest)

```bash
cd samples/xlog_flutter/example/macos
xcodebuild test \
  -project Runner.xcodeproj \
  -scheme Runner \
  -configuration Debug \
  -destination 'platform=macOS'
```

Or open `macos/Runner.xcworkspace` in Xcode and run the `RunnerTests` target (⌘U).

### iOS Native Tests (XCTest)

```bash
cd samples/xlog_flutter/example/ios
xcodebuild test \
  -workspace Runner.xcworkspace \
  -scheme Runner \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

Or open `ios/Runner.xcworkspace` in Xcode and run the `RunnerTests` target (⌘U).

### Android Native Tests (JUnit Instrumented)

Requires a connected device or running emulator.

```bash
cd samples/xlog_flutter/example/android
./gradlew connectedAndroidTest
```

Results are written to `app/build/reports/androidTests/connected/`.

## Test Structure

```
example/
├── integration_test/
│   ├── xlog_all_test.dart            # Single entry point (aggregates all groups)
│   ├── test_utils.dart               # Shared helpers (temp dirs, file utils)
│   ├── xlog_open_cases.dart          # Instance lifecycle tests
│   ├── xlog_write_cases.dart         # Write operations + config tests
│   ├── xlog_level_cases.dart         # Log level control tests
│   ├── xlog_control_cases.dart       # Appender mode / flush tests
│   └── xlog_multi_instance_cases.dart # Multi-instance isolation tests
├── macos/RunnerTests/RunnerTests.swift # macOS XCTest (ObjC wrapper layer)
├── ios/RunnerTests/RunnerTests.swift   # iOS XCTest (ObjC wrapper layer)
└── android/app/src/androidTest/       # Android JUnit instrumented tests
    └── java/com/codexgao/xlog_flutter_example/
        └── XlogNativeInstrumentedTest.kt
```

## Known Behaviors

- `logPath` returns the `logdir` passed to `XLogConfig`, not a per-instance subdirectory.
  Log files inside that directory are named `<nameprefix>_YYYYMMDD.xlog`.
- `XLogLevel.all` and `XLogLevel.verbose` both map to native value `0`.
  Getting the level after setting `verbose` will return `all`.
- Windows and Linux test stubs exist in `windows/runner/` and `linux/runner/`
  but are not yet wired into a test runner.
