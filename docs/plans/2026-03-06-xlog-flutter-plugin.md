# xlog_flutter Plugin Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement the `xlog_flutter` Flutter FFI plugin so that Flutter apps can use the mars xlog logging library on all platforms (Android, iOS, macOS, Windows, Linux).

**Architecture:** A thin C wrapper layer (`src/xlog_flutter.h/cpp`) exposes xlog's C++ API as plain C functions with `FFI_PLUGIN_EXPORT`, which are then bound to Dart via ffigen-generated bindings. A high-level Dart `XLog` static class provides a clean, idiomatic API on top. Each platform's CMakeLists links a prebuilt xlog static library from `libs/<platform>/`.

**Tech Stack:** C++17, mars xlog (appender.h, xloggerbase.h), Flutter FFI (dart:ffi), ffigen 11.x, CMake 3.10+, Dart 3.5+

---

## Context: Key Files

| File | Purpose |
|---|---|
| `samples/xlog_flutter/src/xlog_flutter.h` | C wrapper header — replace entirely |
| `samples/xlog_flutter/src/xlog_flutter.cpp` | C wrapper impl — replace xlog_flutter.c |
| `samples/xlog_flutter/src/CMakeLists.txt` | Build — update to C++, link prebuilt xlog |
| `samples/xlog_flutter/lib/xlog_flutter.dart` | High-level Dart API — replace entirely |
| `samples/xlog_flutter/lib/xlog_flutter_bindings_generated.dart` | Auto-generated FFI bindings — regenerate |
| `samples/xlog_flutter/ffigen.yaml` | ffigen config — update for new header |
| `samples/xlog_flutter/windows/CMakeLists.txt` | Windows platform build — already correct |
| `samples/xlog_flutter/linux/CMakeLists.txt` | Linux platform build — already correct |
| `samples/xlog_flutter/android/build.gradle` | Android build — references ../src/CMakeLists.txt |
| `samples/xlog_flutter/ios/xlog_flutter.podspec` | iOS/macOS podspec — update for xlog |
| `samples/xlog_flutter/example/lib/main.dart` | Example app — replace with xlog demo |
| `mars/xlog/appender.h` | xlog open/close/flush API |
| `mars/xlog/export_include/xlogger/xloggerbase.h` | TLogLevel, XLoggerInfo, xlogger_Write |

## Context: xlog C++ API Summary

```cpp
// Open (call once at startup)
mars::xlog::appender_open(XLogConfig{
    .mode_ = kAppenderAsync,
    .logdir_ = "/path/to/logs",
    .nameprefix_ = "myapp",
    .compress_mode_ = kZlib,
    .cachedir_ = "",
    .cache_days_ = 0,
});

// Write a log entry
XLoggerInfo info{};
info.level    = kLevelInfo;
info.tag      = "MyTag";
info.filename = "file.cpp";
info.func_name = "myFunc";
info.line     = 42;
gettimeofday(&info.timeval, nullptr);
info.pid = xlogger_pid(); info.tid = xlogger_tid(); info.maintid = xlogger_maintid();
xlogger_Write(&info, "my message");

// Control
xlogger_SetLevel(kLevelDebug);
mars::xlog::appender_set_console_log(true);
mars::xlog::appender_flush();
mars::xlog::appender_flush_sync();
mars::xlog::appender_close();
mars::xlog::appender_set_max_file_size(10 * 1024 * 1024);
mars::xlog::appender_set_max_alive_duration(10 * 24 * 3600);
```

---

## Task 1: Write the C wrapper header (`src/xlog_flutter.h`)

**Files:**
- Modify: `samples/xlog_flutter/src/xlog_flutter.h`

Replace the entire file with the xlog C wrapper declarations.

**Step 1: Replace `src/xlog_flutter.h`**

```cpp
#ifndef XLOG_FLUTTER_H_
#define XLOG_FLUTTER_H_

#include <stdint.h>

#if _WIN32
#define FFI_PLUGIN_EXPORT __declspec(dllexport)
#else
#define FFI_PLUGIN_EXPORT __attribute__((visibility("default"))) __attribute__((used))
#endif

#ifdef __cplusplus
extern "C" {
#endif

// Open xlog appender.
// mode: 0=async, 1=sync
// level: 0=verbose, 1=debug, 2=info, 3=warn, 4=error, 5=fatal, 6=none
// compress_mode: 0=zlib, 1=zstd
// logdir, nameprefix, cachedir: UTF-8 strings; cachedir may be NULL/empty
// cache_days: 0 = no cache limit
FFI_PLUGIN_EXPORT void xlog_open(int mode,
                                 int level,
                                 const char* logdir,
                                 const char* nameprefix,
                                 int compress_mode,
                                 const char* cachedir,
                                 int cache_days);

FFI_PLUGIN_EXPORT void xlog_close(void);

// is_sync: 0=async flush, 1=sync flush (blocks until flushed)
FFI_PLUGIN_EXPORT void xlog_flush(int is_sync);

// Write a log entry.
// level: same values as xlog_open's level param
// tag, filename, funcname, message: UTF-8 strings; filename/funcname may be NULL
// line: source line number (0 if unknown)
FFI_PLUGIN_EXPORT void xlog_write(int level,
                                  const char* tag,
                                  const char* filename,
                                  const char* funcname,
                                  int line,
                                  const char* message);

FFI_PLUGIN_EXPORT void xlog_set_console_log(int is_open);
FFI_PLUGIN_EXPORT void xlog_set_level(int level);

// max_bytes: 0 = no file size limit (default)
FFI_PLUGIN_EXPORT void xlog_set_max_file_size(int64_t max_bytes);

// max_seconds: max alive duration in seconds (default: 10 days = 864000)
FFI_PLUGIN_EXPORT void xlog_set_max_alive_duration(int64_t max_seconds);

#ifdef __cplusplus
}
#endif

#endif  // XLOG_FLUTTER_H_
```

**Step 2: Commit**

```bash
git add samples/xlog_flutter/src/xlog_flutter.h
git commit -m "feat(xlog_flutter): add C wrapper header with xlog FFI API"
```

---

## Task 2: Write the C++ wrapper implementation (`src/xlog_flutter.cpp`)

**Files:**
- Create: `samples/xlog_flutter/src/xlog_flutter.cpp`
- Delete (effectively): `samples/xlog_flutter/src/xlog_flutter.c` — will be replaced by CMakeLists change

**Step 1: Create `src/xlog_flutter.cpp`**

```cpp
#include "xlog_flutter.h"

#include <string>
#include <sys/time.h>

#include "appender.h"
#include "xlogger/xloggerbase.h"

using mars::xlog::XLogConfig;
using mars::xlog::kAppenderAsync;
using mars::xlog::kAppenderSync;
using mars::xlog::kZlib;
using mars::xlog::kZstd;

void xlog_open(int mode,
               int level,
               const char* logdir,
               const char* nameprefix,
               int compress_mode,
               const char* cachedir,
               int cache_days) {
    XLogConfig config;
    config.mode_         = (mode == 1) ? kAppenderSync : kAppenderAsync;
    config.logdir_       = logdir ? logdir : "";
    config.nameprefix_   = nameprefix ? nameprefix : "";
    config.compress_mode_ = (compress_mode == 1) ? kZstd : kZlib;
    config.cachedir_     = cachedir ? cachedir : "";
    config.cache_days_   = cache_days;

    mars::xlog::appender_open(config);
    xlogger_SetLevel(static_cast<TLogLevel>(level));
}

void xlog_close(void) {
    mars::xlog::appender_close();
}

void xlog_flush(int is_sync) {
    if (is_sync) {
        mars::xlog::appender_flush_sync();
    } else {
        mars::xlog::appender_flush();
    }
}

void xlog_write(int level,
                const char* tag,
                const char* filename,
                const char* funcname,
                int line,
                const char* message) {
    XLoggerInfo info{};
    info.level     = static_cast<TLogLevel>(level);
    info.tag       = tag;
    info.filename  = filename ? filename : "";
    info.func_name = funcname ? funcname : "";
    info.line      = line;
    gettimeofday(&info.timeval, nullptr);
    info.pid     = xlogger_pid();
    info.tid     = xlogger_tid();
    info.maintid = xlogger_maintid();
    xlogger_Write(&info, message ? message : "");
}

void xlog_set_console_log(int is_open) {
    mars::xlog::appender_set_console_log(is_open != 0);
}

void xlog_set_level(int level) {
    xlogger_SetLevel(static_cast<TLogLevel>(level));
}

void xlog_set_max_file_size(int64_t max_bytes) {
    mars::xlog::appender_set_max_file_size(static_cast<uint64_t>(max_bytes));
}

void xlog_set_max_alive_duration(int64_t max_seconds) {
    mars::xlog::appender_set_max_alive_duration(static_cast<long>(max_seconds));
}
```

**Step 2: Commit**

```bash
git add samples/xlog_flutter/src/xlog_flutter.cpp
git commit -m "feat(xlog_flutter): add C++ wrapper implementation for xlog FFI"
```

---

## Task 3: Update `src/CMakeLists.txt` to build C++ and link xlog

**Files:**
- Modify: `samples/xlog_flutter/src/CMakeLists.txt`

The prebuilt xlog static libraries are expected at these paths (relative to repo root):
- Windows x64: `mars/cmake_build/Windows/Windows.out/win/mars.lib`
  (built via `python build_windows.py --xlog --config Release` from CLAUDE.md)
- Android: built by the Android Gradle plugin — handled via `externalNativeBuild` in `build.gradle`
- iOS/macOS: handled via the podspec
- Linux: `mars/cmake_build/linux/mars.a` (built via cmake)

For the shared `src/CMakeLists.txt` that all platforms include via `add_subdirectory`, we configure include paths and source file. Each platform's own CMakeLists.txt handles linking the prebuilt `.lib`/`.a`.

**Step 1: Replace `src/CMakeLists.txt`**

```cmake
cmake_minimum_required(VERSION 3.10)

project(xlog_flutter_library VERSION 0.0.1 LANGUAGES CXX)

# Mars xlog root (two levels up from samples/xlog_flutter/src/)
set(MARS_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../../mars")

add_library(xlog_flutter SHARED
  "xlog_flutter.cpp"
)

target_include_directories(xlog_flutter PRIVATE
  "${MARS_ROOT}/xlog"
  "${MARS_ROOT}/xlog/export_include"
  "${MARS_ROOT}/comm"
)

set_target_properties(xlog_flutter PROPERTIES
  PUBLIC_HEADER xlog_flutter.h
  OUTPUT_NAME "xlog_flutter"
  CXX_STANDARD 17
  CXX_STANDARD_REQUIRED YES
)

target_compile_definitions(xlog_flutter PUBLIC DART_SHARED_LIB)

# Platform-specific: link prebuilt xlog static library
if(WIN32)
  set(XLOG_LIB_PATH "${MARS_ROOT}/cmake_build/Windows/Windows.out/win/mars.lib")
  if(EXISTS "${XLOG_LIB_PATH}")
    target_link_libraries(xlog_flutter PRIVATE "${XLOG_LIB_PATH}")
  else()
    message(WARNING "xlog prebuilt library not found at ${XLOG_LIB_PATH}. "
                    "Run: cd mars && python build_windows.py --xlog --config Release")
  endif()
elseif(ANDROID)
  # Android links are handled per-ABI; the .a is expected to be in a standard
  # location. Leave this for the Android build (NDK handles linking marsxlog).
  # If using a prebuilt .a, add it here:
  # target_link_libraries(xlog_flutter PRIVATE "${MARS_ROOT}/cmake_build/android/${ANDROID_ABI}/libmarsxlog.a")
elseif(APPLE)
  # iOS/macOS: linking handled by podspec
elseif(UNIX)
  # Linux
  set(XLOG_LIB_PATH "${MARS_ROOT}/cmake_build/linux/libmars.a")
  if(EXISTS "${XLOG_LIB_PATH}")
    target_link_libraries(xlog_flutter PRIVATE "${XLOG_LIB_PATH}")
  else()
    message(WARNING "xlog prebuilt library not found at ${XLOG_LIB_PATH}.")
  endif()
endif()
```

**Step 2: Remove the old `.c` source file** (it's superseded by the `.cpp`):

```bash
git rm samples/xlog_flutter/src/xlog_flutter.c
```

**Step 3: Commit**

```bash
git add samples/xlog_flutter/src/CMakeLists.txt
git commit -m "feat(xlog_flutter): update CMakeLists to C++17, include xlog headers, link prebuilt lib"
```

---

## Task 4: Update iOS/macOS podspec to include xlog sources

**Files:**
- Modify: `samples/xlog_flutter/ios/xlog_flutter.podspec`

The podspec needs to include the xlog source files so CocoaPods can compile them.

**Step 1: Replace `ios/xlog_flutter.podspec`**

```ruby
Pod::Spec.new do |s|
  s.name             = 'xlog_flutter'
  s.version          = '0.0.1'
  s.summary          = 'Flutter FFI plugin wrapping the mars xlog logging library.'
  s.description      = 'Provides Flutter apps with high-performance, reliable logging via WeChat Mars xlog.'
  s.homepage         = 'https://github.com/Tencent/mars'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Tencent' => 'mars@tencent.com' }

  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'

  # Mars root relative to this podspec
  mars_root = File.join(__dir__, '..', '..', '..', 'mars')

  # Include the xlog wrapper from src/
  s.source_files = [
    'Classes/**/*',
    "../src/xlog_flutter.cpp",
    "../src/xlog_flutter.h",
  ]

  # Add xlog source files needed for compilation
  # (If using a prebuilt .a framework instead, replace with s.vendored_libraries)
  xlog_src = File.join(mars_root, 'xlog', 'src')
  comm_src  = File.join(mars_root, 'comm')

  s.pod_target_xcconfig = {
    'DEFINES_MODULE'                        => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]'  => 'i386',
    'HEADER_SEARCH_PATHS'                   => [
      File.join(mars_root, 'xlog'),
      File.join(mars_root, 'xlog', 'export_include'),
      File.join(mars_root, 'comm'),
    ].join(' '),
    'CLANG_CXX_LANGUAGE_STANDARD'          => 'c++17',
  }

  s.dependency 'Flutter'
  s.platform = :ios, '12.0'
  s.swift_version = '5.0'
end
```

**Note:** A full CocoaPods integration would need xlog compiled into a `.framework` or `.a`. The podspec above sets up header search paths; the actual xlog `.a` or source inclusion depends on the build setup. For a self-contained plugin, use `s.vendored_libraries` pointing to a prebuilt `libmarsxlog.a`.

**Step 2: Update `macos/Classes/xlog_flutter.c`** — same as iOS, it just re-includes the cpp:

The file `macos/Classes/xlog_flutter.c` currently has `#include "../../src/xlog_flutter.c"`. Rename the include to the `.cpp` file, or simply delete the file if CMake handles the build on macOS (macOS uses CMake via the Flutter macOS runner, not CocoaPods).

**Step 3: Commit**

```bash
git add samples/xlog_flutter/ios/xlog_flutter.podspec
git add samples/xlog_flutter/macos/Classes/xlog_flutter.c
git commit -m "feat(xlog_flutter): update iOS/macOS podspec for xlog C++ wrapper"
```

---

## Task 5: Update `ffigen.yaml` for the new header

**Files:**
- Modify: `samples/xlog_flutter/ffigen.yaml`

**Step 1: Replace `ffigen.yaml`**

```yaml
# Run with `dart run ffigen --config ffigen.yaml` from samples/xlog_flutter/
name: XlogFlutterBindings
description: |
  Bindings for `src/xlog_flutter.h` — mars xlog FFI wrapper.

  Regenerate bindings with `dart run ffigen --config ffigen.yaml`.
output: 'lib/xlog_flutter_bindings_generated.dart'
headers:
  entry-points:
    - 'src/xlog_flutter.h'
  include-directives:
    - 'src/xlog_flutter.h'
preamble: |
  // ignore_for_file: always_specify_types
  // ignore_for_file: camel_case_types
  // ignore_for_file: non_constant_identifier_names
comments:
  style: any
  length: full
```

**Step 2: Run ffigen to regenerate bindings**

```bash
cd samples/xlog_flutter
dart run ffigen --config ffigen.yaml
```

Expected output: `lib/xlog_flutter_bindings_generated.dart` regenerated with `xlog_open`, `xlog_close`, `xlog_flush`, `xlog_write`, `xlog_set_console_log`, `xlog_set_level`, `xlog_set_max_file_size`, `xlog_set_max_alive_duration`.

**Step 3: Verify the generated file** — open `lib/xlog_flutter_bindings_generated.dart` and confirm it contains a `XlogFlutterBindings` class with methods for each of the 8 exported functions (no `sum` or `sum_long_running`).

**Step 4: Commit**

```bash
git add samples/xlog_flutter/ffigen.yaml
git add samples/xlog_flutter/lib/xlog_flutter_bindings_generated.dart
git commit -m "feat(xlog_flutter): regenerate FFI bindings for xlog API"
```

---

## Task 6: Write the high-level Dart API (`lib/xlog_flutter.dart`)

**Files:**
- Modify: `samples/xlog_flutter/lib/xlog_flutter.dart`

**Step 1: Replace `lib/xlog_flutter.dart` entirely**

```dart
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'xlog_flutter_bindings_generated.dart';

// ---------------------------------------------------------------------------
// Public enumerations
// ---------------------------------------------------------------------------

enum LogLevel {
  verbose, // 0
  debug,   // 1
  info,    // 2
  warn,    // 3
  error,   // 4
  fatal,   // 5
  none,    // 6
}

enum AppenderMode {
  async_, // 0
  sync_,  // 1
}

enum CompressMode {
  zlib, // 0
  zstd, // 1
}

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

class XLogConfig {
  /// Directory where log files are written. Must be writable.
  final String logDir;

  /// Prefix for log file names (e.g. "myapp").
  final String namePrefix;

  /// Minimum log level. Messages below this level are discarded.
  final LogLevel level;

  /// Async (default) or sync write mode.
  final AppenderMode mode;

  /// Compression algorithm used for log files.
  final CompressMode compressMode;

  /// Optional cache directory. Use the app's cache dir to avoid SIGBUS on Android.
  /// If empty, no separate cache is used.
  final String cacheDir;

  /// How many days to keep old log files. 0 = unlimited.
  final int cacheDays;

  const XLogConfig({
    required this.logDir,
    required this.namePrefix,
    this.level = LogLevel.debug,
    this.mode = AppenderMode.async_,
    this.compressMode = CompressMode.zlib,
    this.cacheDir = '',
    this.cacheDays = 0,
  });
}

// ---------------------------------------------------------------------------
// XLog static API
// ---------------------------------------------------------------------------

/// High-level wrapper around the mars xlog C library.
///
/// Usage:
/// ```dart
/// XLog.open(XLogConfig(logDir: '/path/to/logs', namePrefix: 'myapp'));
/// XLog.info('MyTag', 'Application started');
/// // ... at shutdown:
/// XLog.close();
/// ```
class XLog {
  XLog._();

  // -------------------------------------------------------------------------
  // Lifecycle
  // -------------------------------------------------------------------------

  /// Open the xlog appender. Call once at application startup before any
  /// log writes. [config] controls log directory, compression, etc.
  static void open(XLogConfig config) {
    final logDir     = config.logDir.toNativeUtf8();
    final prefix     = config.namePrefix.toNativeUtf8();
    final cacheDir   = config.cacheDir.toNativeUtf8();
    try {
      _bindings.xlog_open(
        config.mode.index,
        config.level.index,
        logDir.cast(),
        prefix.cast(),
        config.compressMode.index,
        cacheDir.cast(),
        config.cacheDays,
      );
    } finally {
      malloc.free(logDir);
      malloc.free(prefix);
      malloc.free(cacheDir);
    }
  }

  /// Flush buffered logs to disk. Returns immediately (async flush).
  static void flush() => _bindings.xlog_flush(0);

  /// Flush buffered logs synchronously. Blocks until all pending data is written.
  static void flushSync() => _bindings.xlog_flush(1);

  /// Close the xlog appender. Flushes remaining data. Call at application shutdown.
  static void close() => _bindings.xlog_close();

  // -------------------------------------------------------------------------
  // Log writing
  // -------------------------------------------------------------------------

  static void verbose(String tag, String message,
      {String filename = '', String funcname = '', int line = 0}) =>
      _write(LogLevel.verbose, tag, message, filename, funcname, line);

  static void debug(String tag, String message,
      {String filename = '', String funcname = '', int line = 0}) =>
      _write(LogLevel.debug, tag, message, filename, funcname, line);

  static void info(String tag, String message,
      {String filename = '', String funcname = '', int line = 0}) =>
      _write(LogLevel.info, tag, message, filename, funcname, line);

  static void warn(String tag, String message,
      {String filename = '', String funcname = '', int line = 0}) =>
      _write(LogLevel.warn, tag, message, filename, funcname, line);

  static void error(String tag, String message,
      {String filename = '', String funcname = '', int line = 0}) =>
      _write(LogLevel.error, tag, message, filename, funcname, line);

  static void fatal(String tag, String message,
      {String filename = '', String funcname = '', int line = 0}) =>
      _write(LogLevel.fatal, tag, message, filename, funcname, line);

  // -------------------------------------------------------------------------
  // Runtime configuration
  // -------------------------------------------------------------------------

  /// Enable or disable console (stdout/logcat) output.
  static void setConsoleLog(bool enable) =>
      _bindings.xlog_set_console_log(enable ? 1 : 0);

  /// Change the minimum log level at runtime.
  static void setLevel(LogLevel level) =>
      _bindings.xlog_set_level(level.index);

  /// Set the maximum size (bytes) for a single log file. 0 = unlimited.
  static void setMaxFileSize(int maxBytes) =>
      _bindings.xlog_set_max_file_size(maxBytes);

  /// Set how long (seconds) to keep old log files. Default 10 days = 864000.
  static void setMaxAliveDuration(int maxSeconds) =>
      _bindings.xlog_set_max_alive_duration(maxSeconds);

  // -------------------------------------------------------------------------
  // Internal
  // -------------------------------------------------------------------------

  static void _write(LogLevel level, String tag, String message,
      String filename, String funcname, int line) {
    final nTag      = tag.toNativeUtf8();
    final nFile     = filename.toNativeUtf8();
    final nFunc     = funcname.toNativeUtf8();
    final nMessage  = message.toNativeUtf8();
    try {
      _bindings.xlog_write(
        level.index,
        nTag.cast(),
        nFile.cast(),
        nFunc.cast(),
        line,
        nMessage.cast(),
      );
    } finally {
      malloc.free(nTag);
      malloc.free(nFile);
      malloc.free(nFunc);
      malloc.free(nMessage);
    }
  }
}

// ---------------------------------------------------------------------------
// Native library loading
// ---------------------------------------------------------------------------

const String _libName = 'xlog_flutter';

final DynamicLibrary _dylib = () {
  if (Platform.isMacOS || Platform.isIOS) {
    return DynamicLibrary.open('$_libName.framework/$_libName');
  }
  if (Platform.isAndroid || Platform.isLinux) {
    return DynamicLibrary.open('lib$_libName.so');
  }
  if (Platform.isWindows) {
    return DynamicLibrary.open('$_libName.dll');
  }
  throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
}();

final XlogFlutterBindings _bindings = XlogFlutterBindings(_dylib);
```

**Step 2: Add `ffi` to runtime dependencies in `pubspec.yaml`**

In `samples/xlog_flutter/pubspec.yaml`, move `ffi` from `dev_dependencies` to `dependencies`:

```yaml
dependencies:
  flutter:
    sdk: flutter
  ffi: ^2.1.0
  plugin_platform_interface: ^2.0.2

dev_dependencies:
  ffigen: ^11.0.0
  flutter_test:
    sdk: flutter
  flutter_lints: ^4.0.0
```

**Step 3: Commit**

```bash
git add samples/xlog_flutter/lib/xlog_flutter.dart
git add samples/xlog_flutter/pubspec.yaml
git commit -m "feat(xlog_flutter): implement high-level Dart XLog API"
```

---

## Task 7: Update the example app (`example/lib/main.dart`)

**Files:**
- Modify: `samples/xlog_flutter/example/lib/main.dart`
- Modify: `samples/xlog_flutter/example/pubspec.yaml` (add path_provider)

The example app demonstrates opening xlog, writing logs at each level, flushing, and closing.

**Step 1: Add `path_provider` to `example/pubspec.yaml`**

```yaml
dependencies:
  flutter:
    sdk: flutter
  xlog_flutter:
    path: ../
  path_provider: ^2.1.0
```

**Step 2: Replace `example/lib/main.dart`**

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:xlog_flutter/xlog_flutter.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String _status = 'Not initialized';
  bool _opened = false;

  Future<void> _openXlog() async {
    final dir = await getApplicationDocumentsDirectory();
    final logDir = Directory('${dir.path}/xlog');
    await logDir.create(recursive: true);

    XLog.open(XLogConfig(
      logDir: logDir.path,
      namePrefix: 'xlog_flutter_demo',
      level: LogLevel.verbose,
      mode: AppenderMode.async_,
    ));
    XLog.setConsoleLog(true);

    setState(() {
      _opened = true;
      _status = 'Opened. Log dir: ${logDir.path}';
    });
  }

  void _writeLogs() {
    if (!_opened) return;
    XLog.verbose('Demo', 'This is a verbose log');
    XLog.debug('Demo', 'This is a debug log');
    XLog.info('Demo', 'This is an info log');
    XLog.warn('Demo', 'This is a warning log');
    XLog.error('Demo', 'This is an error log');
    setState(() => _status = 'Wrote 5 log entries.');
  }

  void _flush() {
    if (!_opened) return;
    XLog.flushSync();
    setState(() => _status = 'Flushed to disk.');
  }

  void _close() {
    if (!_opened) return;
    XLog.close();
    setState(() {
      _opened = false;
      _status = 'Closed.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('xlog_flutter Demo')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(_status, style: const TextStyle(fontSize: 14)),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _openXlog, child: const Text('Open XLog')),
              ElevatedButton(onPressed: _writeLogs, child: const Text('Write Logs')),
              ElevatedButton(onPressed: _flush,    child: const Text('Flush Sync')),
              ElevatedButton(onPressed: _close,    child: const Text('Close XLog')),
            ],
          ),
        ),
      ),
    );
  }
}
```

**Step 3: Commit**

```bash
git add samples/xlog_flutter/example/lib/main.dart
git add samples/xlog_flutter/example/pubspec.yaml
git commit -m "feat(xlog_flutter): update example app to demonstrate xlog API"
```

---

## Task 8: Build and verify (Windows)

This task verifies the plugin compiles and links correctly on Windows, since that's the current dev environment.

**Prerequisites:** Visual Studio 2022, CMake, Python 3.10+, Flutter SDK installed.

**Step 1: Build the xlog static library for Windows**

```bash
cd mars
python build_windows.py --xlog --config Release
```

Expected: `mars/cmake_build/Windows/Windows.out/win/mars.lib` created.

**Step 2: Run the Flutter example app on Windows**

```bash
cd samples/xlog_flutter/example
flutter pub get
flutter run -d windows
```

Expected: App launches showing "xlog_flutter Demo". Tap "Open XLog", "Write Logs", "Flush Sync" in sequence. No crashes.

**Step 3: Verify log file created**

Check `%USERPROFILE%\Documents\xlog_flutter_demo*.xlog` or whatever `getApplicationDocumentsDirectory()` returns on Windows. A log file should exist.

**Step 4: Fix any compilation errors**, then commit fixes.

---

## Task 9: Android build configuration

**Files:**
- Modify: `samples/xlog_flutter/android/build.gradle` (if needed)
- Modify: `samples/xlog_flutter/src/CMakeLists.txt` (Android-specific section)

Android uses the NDK to compile xlog sources. The `android/build.gradle` already points to `../src/CMakeLists.txt`. The NDK will compile `xlog_flutter.cpp`. We need to also compile the xlog C++ sources.

**Option A (recommended for this sample): Build xlog sources directly in Android CMakeLists**

Add xlog source files directly to the target in `src/CMakeLists.txt` for Android:

In the `if(ANDROID)` block of `src/CMakeLists.txt`, add:

```cmake
elseif(ANDROID)
  file(GLOB_RECURSE XLOG_SOURCES
    "${MARS_ROOT}/xlog/src/*.cc"
    "${MARS_ROOT}/xlog/src/*.cpp"
    "${MARS_ROOT}/comm/*.cc"
    "${MARS_ROOT}/comm/*.cpp"
  )
  # Exclude platform-specific files that don't apply
  list(FILTER XLOG_SOURCES EXCLUDE REGEX ".*_test.*")
  list(FILTER XLOG_SOURCES EXCLUDE REGEX ".*/win/.*")
  list(FILTER XLOG_SOURCES EXCLUDE REGEX ".*/apple/.*")
  target_sources(xlog_flutter PRIVATE ${XLOG_SOURCES})
  target_link_libraries(xlog_flutter PRIVATE log z)
```

**Step 1: Update CMakeLists.txt Android section** as above.

**Step 2: Test Android build**

```bash
cd samples/xlog_flutter/example
flutter run -d <android-device-or-emulator>
```

**Step 3: Commit**

```bash
git add samples/xlog_flutter/src/CMakeLists.txt
git commit -m "feat(xlog_flutter): add Android NDK xlog source compilation"
```

---

## Summary: File Change List

| File | Action |
|---|---|
| `samples/xlog_flutter/src/xlog_flutter.h` | Replace with xlog C wrapper header |
| `samples/xlog_flutter/src/xlog_flutter.c` | Delete (replaced by .cpp) |
| `samples/xlog_flutter/src/xlog_flutter.cpp` | Create — C++ wrapper implementation |
| `samples/xlog_flutter/src/CMakeLists.txt` | Replace — C++17, xlog includes, link prebuilt |
| `samples/xlog_flutter/ffigen.yaml` | Update description only (functionally same) |
| `samples/xlog_flutter/lib/xlog_flutter_bindings_generated.dart` | Regenerate via ffigen |
| `samples/xlog_flutter/lib/xlog_flutter.dart` | Replace — XLog static class API |
| `samples/xlog_flutter/pubspec.yaml` | Move `ffi` to runtime dependencies |
| `samples/xlog_flutter/ios/xlog_flutter.podspec` | Update for xlog C++ |
| `samples/xlog_flutter/example/lib/main.dart` | Replace — xlog demo app |
| `samples/xlog_flutter/example/pubspec.yaml` | Add path_provider |

## Notes on Prebuilt Libraries

The plugin expects prebuilt static libraries at these paths (relative to repo root):

| Platform | Build command | Expected output |
|---|---|---|
| Windows x64 | `cd mars && python build_windows.py --xlog --config Release` | `mars/cmake_build/Windows/Windows.out/win/mars.lib` |
| Linux x64 | `cd mars && mkdir -p cmake_build/linux && cd cmake_build/linux && cmake ../.. && cmake --build . --target marsxlog` | `mars/cmake_build/linux/libmarsxlog.a` |
| Android | Built automatically by NDK during `flutter run` | N/A (sources compiled inline) |
| iOS/macOS | `cd mars && python build_ios.py` / `build_osx.py` | `mars.framework` |
