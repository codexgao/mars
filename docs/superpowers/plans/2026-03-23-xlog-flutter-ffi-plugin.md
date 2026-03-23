# xlog_flutter FFI Plugin Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Flutter FFI plugin that wraps mars xlog via a C API layer, verified on Windows.

**Architecture:** C wrapper (`mars/xlog/capi/`) compiled into xlog.dll provides `extern "C"` functions. Flutter plugin uses `dart:ffi` + ffigen-generated bindings to call these functions. High-level Dart API (`XLog`/`XLogInstance`) manages instances and memory.

**Tech Stack:** C/C++, CMake, Dart 3.5, Flutter 3.24, package:ffi, package:ffigen

---

## Chunk 1: C API Layer

### Task 1: Create `xlog_capi.h`

**Files:**
- Create: `mars/xlog/capi/xlog_capi.h`

- [ ] **Step 1: Create the C API header file**

```c
// mars/xlog/capi/xlog_capi.h
#ifndef MARS_XLOG_CAPI_H_
#define MARS_XLOG_CAPI_H_

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32)
  #ifdef XLOG_CAPI_EXPORT
    #define XLOG_API __declspec(dllexport)
  #else
    #define XLOG_API __declspec(dllimport)
  #endif
#elif defined(__GNUC__) || defined(__clang__)
  #define XLOG_API __attribute__((visibility("default")))
#else
  #define XLOG_API
#endif

typedef enum {
    XLOG_LEVEL_ALL = 0,
    XLOG_LEVEL_VERBOSE = 0,
    XLOG_LEVEL_DEBUG = 1,
    XLOG_LEVEL_INFO = 2,
    XLOG_LEVEL_WARN = 3,
    XLOG_LEVEL_ERROR = 4,
    XLOG_LEVEL_FATAL = 5,
    XLOG_LEVEL_NONE = 6,
} xlog_level_t;

typedef enum {
    XLOG_APPENDER_ASYNC = 0,
    XLOG_APPENDER_SYNC = 1,
} xlog_appender_mode_t;

typedef enum {
    XLOG_COMPRESS_ZLIB = 0,
    XLOG_COMPRESS_ZSTD = 1,
} xlog_compress_mode_t;

typedef struct {
    xlog_appender_mode_t  mode;
    const char*           logdir;
    const char*           nameprefix;
    const char*           pub_key;
    xlog_compress_mode_t  compress_mode;
    int                   compress_level;
    const char*           cachedir;
    int                   cache_days;
} xlog_config_t;

/* Instance lifecycle */
XLOG_API uintptr_t  xlog_new_instance(const xlog_config_t* config, xlog_level_t level);
XLOG_API uintptr_t  xlog_get_instance(const char* nameprefix);
XLOG_API int        xlog_has_instance(const char* nameprefix);
XLOG_API void       xlog_release_instance(const char* nameprefix);
XLOG_API void       xlog_destroy_instance(uintptr_t instance);

/* Log writing */
XLOG_API void xlog_write(uintptr_t instance, xlog_level_t level,
                          const char* tag, const char* filename,
                          const char* funcname, int line,
                          const char* log);

/* Log level */
XLOG_API int          xlog_is_enabled_for(uintptr_t instance, xlog_level_t level);
XLOG_API xlog_level_t xlog_get_level(uintptr_t instance);
XLOG_API void         xlog_set_level(uintptr_t instance, xlog_level_t level);

/* Control */
XLOG_API void xlog_set_appender_mode(uintptr_t instance, xlog_appender_mode_t mode);
XLOG_API void xlog_set_console_log_open(uintptr_t instance, int is_open);
XLOG_API void xlog_flush(uintptr_t instance, int is_sync);
XLOG_API void xlog_flush_all(int is_sync);

/* Path query */
XLOG_API int xlog_get_log_path(uintptr_t instance, char* buf, unsigned int buf_len);

#ifdef __cplusplus
}
#endif

#endif /* MARS_XLOG_CAPI_H_ */
```

- [ ] **Step 2: Commit**

```bash
git add mars/xlog/capi/xlog_capi.h
git commit -m "feat(xlog): add C API header for FFI consumers"
```

### Task 2: Create `xlog_capi.cc`

**Files:**
- Create: `mars/xlog/capi/xlog_capi.cc`

**Reference:** The implementation wraps C++ functions from `mars/xlog/xlogger_interface.h` (namespace `mars::xlog`). Key C++ types:
- `mars::xlog::XLogConfig` — struct with `std::string` fields (see `mars/xlog/xlog_config.h`)
- `mars::xlog::TAppenderMode` — enum: `kAppenderAsync=0, kAppenderSync=1`
- `mars::xlog::TCompressMode` — enum: `kZlib=0, kZstd=1`
- `TLogLevel` — enum in `xloggerbase.h`: `kLevelAll=0` through `kLevelNone=6`
- `XLoggerInfo` — struct with `level, tag, filename, func_name, line, timeval, pid, tid, maintid, traceLog`

- [ ] **Step 1: Write the implementation**

```cpp
// mars/xlog/capi/xlog_capi.cc
#include "mars/xlog/capi/xlog_capi.h"

#include <string.h>
#include <sys/time.h>

#ifdef _WIN32
#include <process.h>
#include <windows.h>
#else
#include <unistd.h>
#include <pthread.h>
#endif

#include "mars/xlog/xlogger_interface.h"
#include "mars/comm/xlogger/xloggerbase.h"

// Helper: NULL-safe string to std::string
static inline std::string SafeStr(const char* s) {
    return s ? std::string(s) : std::string();
}

// Helper: get current time
static inline struct timeval GetTimeOfDay() {
    struct timeval tv = {0, 0};
#ifdef _WIN32
    FILETIME ft;
    GetSystemTimeAsFileTime(&ft);
    ULARGE_INTEGER uli;
    uli.LowPart = ft.dwLowDateTime;
    uli.HighPart = ft.dwHighDateTime;
    // Convert from 100-ns intervals since 1601 to Unix epoch
    uli.QuadPart -= 116444736000000000ULL;
    tv.tv_sec = (long)(uli.QuadPart / 10000000ULL);
    tv.tv_usec = (long)((uli.QuadPart % 10000000ULL) / 10);
#else
    gettimeofday(&tv, nullptr);
#endif
    return tv;
}

// Helper: get current process ID
static inline intmax_t GetPid() {
#ifdef _WIN32
    return (intmax_t)_getpid();
#else
    return (intmax_t)getpid();
#endif
}

// Helper: get current thread ID
static inline intmax_t GetTid() {
#ifdef _WIN32
    return (intmax_t)GetCurrentThreadId();
#else
    return (intmax_t)pthread_self();
#endif
}

extern "C" {

uintptr_t xlog_new_instance(const xlog_config_t* config, xlog_level_t level) {
    if (!config || !config->logdir || !config->nameprefix) {
        return 0;
    }

    mars::xlog::XLogConfig cpp_config;
    cpp_config.mode_ = static_cast<mars::xlog::TAppenderMode>(config->mode);
    cpp_config.logdir_ = config->logdir;
    cpp_config.nameprefix_ = config->nameprefix;
    cpp_config.pub_key_ = SafeStr(config->pub_key);
    cpp_config.compress_mode_ = static_cast<mars::xlog::TCompressMode>(config->compress_mode);
    cpp_config.compress_level_ = config->compress_level;
    cpp_config.cachedir_ = SafeStr(config->cachedir);
    cpp_config.cache_days_ = config->cache_days;

    return mars::xlog::NewXloggerInstance(cpp_config, static_cast<TLogLevel>(level));
}

uintptr_t xlog_get_instance(const char* nameprefix) {
    if (!nameprefix) return 0;
    return mars::xlog::GetXloggerInstance(nameprefix);
}

int xlog_has_instance(const char* nameprefix) {
    if (!nameprefix) return 0;
    return mars::xlog::HasXlogInstance(nameprefix) ? 1 : 0;
}

void xlog_release_instance(const char* nameprefix) {
    if (!nameprefix) return;
    mars::xlog::ReleaseXloggerInstance(nameprefix);
}

void xlog_destroy_instance(uintptr_t instance) {
    mars::xlog::DestroyXlogInstance(instance);
}

void xlog_write(uintptr_t instance, xlog_level_t level,
                const char* tag, const char* filename,
                const char* funcname, int line,
                const char* log) {
    if (0 == instance || !log) return;

    XLoggerInfo info = XLOGGER_INFO_INITIALIZER;
    info.level = static_cast<TLogLevel>(level);
    info.tag = tag ? tag : "";
    info.filename = filename ? filename : "";
    info.func_name = funcname ? funcname : "";
    info.line = line;
    info.timeval = GetTimeOfDay();
    info.pid = GetPid();
    info.tid = GetTid();
    info.maintid = 0;
    info.traceLog = 0;

    mars::xlog::XloggerWrite(instance, &info, log);
}

int xlog_is_enabled_for(uintptr_t instance, xlog_level_t level) {
    return mars::xlog::IsEnabledFor(instance, static_cast<TLogLevel>(level)) ? 1 : 0;
}

xlog_level_t xlog_get_level(uintptr_t instance) {
    return static_cast<xlog_level_t>(mars::xlog::GetLevel(instance));
}

void xlog_set_level(uintptr_t instance, xlog_level_t level) {
    mars::xlog::SetLevel(instance, static_cast<TLogLevel>(level));
}

void xlog_set_appender_mode(uintptr_t instance, xlog_appender_mode_t mode) {
    mars::xlog::SetAppenderMode(instance, static_cast<mars::xlog::TAppenderMode>(mode));
}

void xlog_set_console_log_open(uintptr_t instance, int is_open) {
    mars::xlog::SetConsoleLogOpen(instance, is_open != 0);
}

void xlog_flush(uintptr_t instance, int is_sync) {
    mars::xlog::Flush(instance, is_sync != 0);
}

void xlog_flush_all(int is_sync) {
    mars::xlog::FlushAll(is_sync != 0);
}

int xlog_get_log_path(uintptr_t instance, char* buf, unsigned int buf_len) {
    if (!buf || buf_len == 0) return 0;
    return mars::xlog::GetCurrentLogPath(instance, buf, buf_len) ? 1 : 0;
}

} // extern "C"
```

- [ ] **Step 2: Commit**

```bash
git add mars/xlog/capi/xlog_capi.cc
git commit -m "feat(xlog): add C API implementation wrapping multi-instance API"
```

### Task 3: Integrate C API into DLL build

**Files:**
- Modify: `mars/xlog/CMakeLists_dll.txt:66` (add capi glob and compile definition)
- Modify: `mars/mars_utils.py:95-98` (add xlog_capi.h to XLOG_COPY_HEADER_FILES)

- [ ] **Step 1: Update CMakeLists_dll.txt**

In `mars/xlog/CMakeLists_dll.txt`, after the existing `set(ALL_XLOG_SRC ...)` line (line 66), change to include capi files:

```cmake
# Replace existing line 66:
#   set(ALL_XLOG_SRC ${XLOG_SRC_FILES} ${XLOG_CRYPT_FILES})
# With:

# C API wrapper files
file(GLOB XLOG_CAPI_FILES
    ${XLOG_ROOT}/capi/*.cc
    ${XLOG_ROOT}/capi/*.h
)

set(ALL_XLOG_SRC ${XLOG_SRC_FILES} ${XLOG_CRYPT_FILES} ${XLOG_CAPI_FILES})
```

After the `add_library(xlog_dll ...)` line, add the compile definition:

```cmake
target_compile_definitions(xlog_dll PRIVATE XLOG_CAPI_EXPORT)
```

Also add include directory for the capi header to be findable:

```cmake
include_directories(${XLOG_ROOT}/capi)
```

- [ ] **Step 2: Update mars_utils.py to export xlog_capi.h**

In `mars/mars_utils.py`, add to `XLOG_COPY_HEADER_FILES` dict (after the `xlogger_interface.h` entry at line 97):

```python
    "mars/xlog/capi/xlog_capi.h": "xlog",
```

Also add the same entry to `COMM_COPY_HEADER_FILES` (after line 51):

```python
    "mars/xlog/capi/xlog_capi.h": "xlog",
```

- [ ] **Step 3: Rebuild xlog.dll to verify compilation**

```bash
cd mars/xlog
python build_windows.py --config Release --incremental
```

Expected: Build succeeds. `xlog_capi.h` appears in `build/windows/include/xlog/xlog_capi.h`. The DLL exports the C API functions.

- [ ] **Step 4: Verify exported symbols include C API functions**

```bash
dumpbin /exports mars/xlog/build/windows/Release/xlog.dll | findstr xlog_
```

Expected: Lines containing `xlog_new_instance`, `xlog_write`, `xlog_flush`, etc.

- [ ] **Step 5: Commit**

```bash
git add mars/xlog/CMakeLists_dll.txt mars/mars_utils.py
git commit -m "feat(xlog): integrate C API layer into DLL build and header export"
```

## Chunk 2: Flutter Plugin Skeleton

### Task 4: Create Flutter plugin project

**Files:**
- Create: `samples/xlog_flutter/` (entire directory via flutter create)

- [ ] **Step 1: Create plugin skeleton**

```bash
cd samples
flutter create --template=plugin_ffi --org com.codexgao --platforms=windows,linux,macos,ios,android xlog_flutter
```

Expected: `samples/xlog_flutter/` created with standard FFI plugin structure.

- [ ] **Step 2: Verify skeleton builds**

```bash
cd samples/xlog_flutter/example
flutter build windows
```

Expected: Builds successfully (the template includes a dummy native function).

- [ ] **Step 3: Commit the generated skeleton**

```bash
git add samples/xlog_flutter/
git commit -m "feat(xlog_flutter): scaffold Flutter FFI plugin via flutter create"
```

### Task 5: Configure ffigen and generate bindings

**Files:**
- Create: `samples/xlog_flutter/ffigen.yaml`
- Modify: `samples/xlog_flutter/pubspec.yaml` (add ffigen dev dependency)
- Create/Replace: `samples/xlog_flutter/lib/src/xlog_bindings.dart` (generated)

- [ ] **Step 1: Add ffigen dependency to pubspec.yaml**

In `samples/xlog_flutter/pubspec.yaml`, add under `dev_dependencies`:

```yaml
dev_dependencies:
  # ... existing entries ...
  ffigen: ^14.0.0
```

Also ensure `dependencies` has:

```yaml
dependencies:
  flutter:
    sdk: flutter
  ffi: ^2.0.0
```

- [ ] **Step 2: Create ffigen.yaml**

```yaml
# samples/xlog_flutter/ffigen.yaml
name: XLogBindings
description: FFI bindings for xlog C API
output: 'lib/src/xlog_flutter_bindings_generated.dart'
headers:
  entry-points:
    - '../../mars/xlog/capi/xlog_capi.h'
  include-directives:
    - '**xlog_capi.h'
preamble: |
  // AUTO GENERATED FILE - DO NOT EDIT
  // Generated by `dart run ffigen`
comments:
  style: any
  length: full
```

- [ ] **Step 3: Run ffigen**

```bash
cd samples/xlog_flutter
dart pub get
dart run ffigen
```

Expected: `lib/src/xlog_flutter_bindings_generated.dart` generated successfully with `XLogBindings` class containing all function bindings.

- [ ] **Step 4: Verify generated file contains expected bindings**

Check the generated file contains: `xlog_new_instance`, `xlog_write`, `xlog_flush`, `xlog_config_t`, `xlog_level_t`, etc.

- [ ] **Step 5: Commit**

```bash
git add samples/xlog_flutter/ffigen.yaml samples/xlog_flutter/pubspec.yaml samples/xlog_flutter/lib/src/xlog_flutter_bindings_generated.dart
git commit -m "feat(xlog_flutter): configure ffigen and generate FFI bindings from xlog_capi.h"
```

### Task 6: Implement Dart high-level API

**Files:**
- Create: `samples/xlog_flutter/lib/src/xlog.dart`
- Modify: `samples/xlog_flutter/lib/xlog_flutter.dart` (re-export)

- [ ] **Step 1: Write xlog.dart**

```dart
// samples/xlog_flutter/lib/src/xlog.dart
import 'dart:ffi';
import 'dart:io' show Platform;
import 'package:ffi/ffi.dart';

import 'xlog_flutter_bindings_generated.dart';

/// Log levels matching xlog_level_t
enum XLogLevel {
  all(0),
  verbose(0),
  debug(1),
  info(2),
  warn(3),
  error(4),
  fatal(5),
  none(6);

  final int value;
  const XLogLevel(this.value);
}

/// Appender modes matching xlog_appender_mode_t
enum XLogAppenderMode {
  async_(0),
  sync_(1);

  final int value;
  const XLogAppenderMode(this.value);
}

/// Compress modes matching xlog_compress_mode_t
enum XLogCompressMode {
  zlib(0),
  zstd(1);

  final int value;
  const XLogCompressMode(this.value);
}

/// Configuration for creating an xlog instance.
class XLogConfig {
  final String logdir;
  final String nameprefix;
  final XLogAppenderMode mode;
  final String? pubKey;
  final XLogCompressMode compressMode;
  final int compressLevel;
  final String? cachedir;
  final int cacheDays;

  const XLogConfig({
    required this.logdir,
    required this.nameprefix,
    this.mode = XLogAppenderMode.async_,
    this.pubKey,
    this.compressMode = XLogCompressMode.zlib,
    this.compressLevel = 6,
    this.cachedir,
    this.cacheDays = 0,
  });
}

/// A handle to a single xlog instance.
class XLogInstance {
  final int _ptr;
  final String nameprefix;
  final XLogBindings _bindings;

  XLogInstance._(this._ptr, this.nameprefix, this._bindings);

  /// Whether this instance handle is valid (non-zero).
  bool get isValid => _ptr != 0;

  void verbose(String tag, String msg) => _write(XLogLevel.verbose, tag, msg);
  void debug(String tag, String msg) => _write(XLogLevel.debug, tag, msg);
  void info(String tag, String msg) => _write(XLogLevel.info, tag, msg);
  void warn(String tag, String msg) => _write(XLogLevel.warn, tag, msg);
  void error(String tag, String msg) => _write(XLogLevel.error, tag, msg);
  void fatal(String tag, String msg) => _write(XLogLevel.fatal, tag, msg);

  bool isEnabledFor(XLogLevel level) {
    return _bindings.xlog_is_enabled_for(_ptr, level.value) != 0;
  }

  XLogLevel get level {
    final v = _bindings.xlog_get_level(_ptr);
    return XLogLevel.values.firstWhere((e) => e.value == v,
        orElse: () => XLogLevel.none);
  }

  set level(XLogLevel value) {
    _bindings.xlog_set_level(_ptr, value.value);
  }

  set appenderMode(XLogAppenderMode value) {
    _bindings.xlog_set_appender_mode(_ptr, value.value);
  }

  set consoleLogOpen(bool value) {
    _bindings.xlog_set_console_log_open(_ptr, value ? 1 : 0);
  }

  void flush({bool sync = false}) {
    _bindings.xlog_flush(_ptr, sync ? 1 : 0);
  }

  String? get logPath {
    final buf = calloc<Uint8>(1024);
    try {
      final ok = _bindings.xlog_get_log_path(_ptr, buf.cast(), 1024);
      if (ok != 0) {
        return buf.cast<Utf8>().toDartString();
      }
      return null;
    } finally {
      calloc.free(buf);
    }
  }

  void _write(XLogLevel level, String tag, String msg) {
    final tagN = tag.toNativeUtf8();
    final msgN = msg.toNativeUtf8();
    final emptyN = ''.toNativeUtf8();
    try {
      _bindings.xlog_write(
        _ptr,
        level.value,
        tagN.cast(),
        emptyN.cast(), // filename
        emptyN.cast(), // funcname
        0,             // line
        msgN.cast(),
      );
    } finally {
      calloc.free(tagN);
      calloc.free(msgN);
      calloc.free(emptyN);
    }
  }
}

/// Global xlog manager. Call [XLog.initialize] before any other method.
class XLog {
  static XLog? _instance;
  late final XLogBindings _bindings;

  XLog._();

  /// Initialize xlog by loading the native library.
  static XLog initialize() {
    if (_instance != null) return _instance!;

    final DynamicLibrary lib;
    if (Platform.isWindows) {
      lib = DynamicLibrary.open('xlog.dll');
    } else if (Platform.isMacOS) {
      lib = DynamicLibrary.open('libxlog.dylib');
    } else if (Platform.isLinux) {
      lib = DynamicLibrary.open('libxlog.so');
    } else if (Platform.isIOS) {
      lib = DynamicLibrary.process();
    } else if (Platform.isAndroid) {
      lib = DynamicLibrary.open('libxlog.so');
    } else {
      throw UnsupportedError(
          'XLog is not supported on this platform: ${Platform.operatingSystem}');
    }

    final xlog = XLog._();
    xlog._bindings = XLogBindings(lib);
    _instance = xlog;
    return xlog;
  }

  /// Get the singleton instance. Throws if not initialized.
  static XLog get instance {
    if (_instance == null) {
      throw StateError('XLog not initialized. Call XLog.initialize() first.');
    }
    return _instance!;
  }

  /// Create a new xlog instance with the given config.
  XLogInstance open(XLogConfig config, {XLogLevel level = XLogLevel.info}) {
    final nativeConfig = calloc<xlog_config_t>();
    final logdirN = config.logdir.toNativeUtf8();
    final prefixN = config.nameprefix.toNativeUtf8();
    final pubKeyN = config.pubKey?.toNativeUtf8();
    final cachedirN = config.cachedir?.toNativeUtf8();

    try {
      nativeConfig.ref.mode = config.mode.value;
      nativeConfig.ref.logdir = logdirN.cast();
      nativeConfig.ref.nameprefix = prefixN.cast();
      nativeConfig.ref.pub_key =
          pubKeyN?.cast() ?? Pointer<Char>.fromAddress(0);
      nativeConfig.ref.compress_mode = config.compressMode.value;
      nativeConfig.ref.compress_level = config.compressLevel;
      nativeConfig.ref.cachedir =
          cachedirN?.cast() ?? Pointer<Char>.fromAddress(0);
      nativeConfig.ref.cache_days = config.cacheDays;

      final ptr = _bindings.xlog_new_instance(nativeConfig, level.value);
      return XLogInstance._(ptr, config.nameprefix, _bindings);
    } finally {
      calloc.free(logdirN);
      calloc.free(prefixN);
      if (pubKeyN != null) calloc.free(pubKeyN);
      if (cachedirN != null) calloc.free(cachedirN);
      calloc.free(nativeConfig);
    }
  }

  /// Get an existing instance by name prefix.
  XLogInstance? get(String nameprefix) {
    final prefixN = nameprefix.toNativeUtf8();
    try {
      final ptr = _bindings.xlog_get_instance(prefixN.cast());
      if (ptr == 0) return null;
      return XLogInstance._(ptr, nameprefix, _bindings);
    } finally {
      calloc.free(prefixN);
    }
  }

  /// Check if an instance exists.
  bool has(String nameprefix) {
    final prefixN = nameprefix.toNativeUtf8();
    try {
      return _bindings.xlog_has_instance(prefixN.cast()) != 0;
    } finally {
      calloc.free(prefixN);
    }
  }

  /// Release an instance by name prefix.
  void release(String nameprefix) {
    final prefixN = nameprefix.toNativeUtf8();
    try {
      _bindings.xlog_release_instance(prefixN.cast());
    } finally {
      calloc.free(prefixN);
    }
  }

  /// Flush all instances.
  void flushAll({bool sync = false}) {
    _bindings.xlog_flush_all(sync ? 1 : 0);
  }
}
```

**Note:** The exact field access syntax on the generated `xlog_config_t` struct (e.g., `nativeConfig.ref.mode`) depends on what ffigen generates. After running ffigen in Task 5, verify the generated struct field names and adjust this code accordingly. The field names in ffigen output typically match the C struct field names exactly.

- [ ] **Step 2: Update the public export file**

Replace the contents of `samples/xlog_flutter/lib/xlog_flutter.dart`:

```dart
// samples/xlog_flutter/lib/xlog_flutter.dart
export 'src/xlog.dart';
```

- [ ] **Step 3: Clean up template files**

Remove the template-generated files that are no longer needed:
- `lib/xlog_flutter.dart` (already replaced above)
- `lib/src/xlog_flutter.dart` (template default, replaced by xlog.dart)

- [ ] **Step 4: Commit**

```bash
git add samples/xlog_flutter/lib/
git commit -m "feat(xlog_flutter): implement high-level Dart API (XLog, XLogInstance, XLogConfig)"
```

## Chunk 3: Windows Platform Integration

### Task 7: Configure Windows CMakeLists.txt

**Files:**
- Modify: `samples/xlog_flutter/windows/CMakeLists.txt`

- [ ] **Step 1: Replace Windows CMakeLists.txt**

Replace the contents of `samples/xlog_flutter/windows/CMakeLists.txt` with:

```cmake
cmake_minimum_required(VERSION 3.14)
project(xlog_flutter_plugin LANGUAGES C CXX)

# Prebuilt xlog DLL location (relative to this CMakeLists.txt)
set(XLOG_PREBUILT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../../mars/xlog/build/windows")

# Validate prebuilt files exist
if(NOT EXISTS "${XLOG_PREBUILT_DIR}/Release/xlog.dll")
  message(FATAL_ERROR
    "Prebuilt xlog.dll not found at ${XLOG_PREBUILT_DIR}/Release/xlog.dll\n"
    "Run: cd mars/xlog && python build_windows.py --config Release")
endif()

# Declare imported shared library
add_library(xlog_flutter SHARED IMPORTED GLOBAL)
set_target_properties(xlog_flutter PROPERTIES
  IMPORTED_IMPLIB "${XLOG_PREBUILT_DIR}/Release/xlog.lib"
  IMPORTED_LOCATION "${XLOG_PREBUILT_DIR}/Release/xlog.dll"
)

# Install DLL into Flutter app bundle
install(FILES "${XLOG_PREBUILT_DIR}/Release/xlog.dll"
  DESTINATION "${CMAKE_INSTALL_PREFIX}"
)

# Expose headers for native consumers who link this plugin
target_include_directories(xlog_flutter INTERFACE
  "${XLOG_PREBUILT_DIR}/include"
)
```

- [ ] **Step 2: Commit**

```bash
git add samples/xlog_flutter/windows/CMakeLists.txt
git commit -m "feat(xlog_flutter): configure Windows CMake to bundle prebuilt xlog.dll"
```

### Task 8: Build and verify DLL bundling

- [ ] **Step 1: Build example app for Windows**

```bash
cd samples/xlog_flutter/example
flutter build windows --release
```

Expected: Build succeeds.

- [ ] **Step 2: Verify xlog.dll is in the bundle**

```bash
ls build/windows/x64/runner/Release/xlog.dll
```

Expected: `xlog.dll` present in the app bundle directory.

- [ ] **Step 3: Commit any build fixes if needed**

## Chunk 4: Example App & Verification

### Task 9: Implement example app

**Files:**
- Modify: `samples/xlog_flutter/example/lib/main.dart`
- Modify: `samples/xlog_flutter/example/pubspec.yaml` (add path_provider or use hardcoded path)

- [ ] **Step 1: Update example pubspec.yaml**

Add `path_provider` to `samples/xlog_flutter/example/pubspec.yaml` dependencies:

```yaml
dependencies:
  flutter:
    sdk: flutter
  xlog_flutter:
    path: ../
  path_provider: ^2.0.0
```

- [ ] **Step 2: Write example app main.dart**

Replace `samples/xlog_flutter/example/lib/main.dart`:

```dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:xlog_flutter/xlog_flutter.dart';

void main() {
  runApp(const XLogExampleApp());
}

class XLogExampleApp extends StatelessWidget {
  const XLogExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'XLog Flutter Example',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const XLogTestPage(),
    );
  }
}

class XLogTestPage extends StatefulWidget {
  const XLogTestPage({super.key});

  @override
  State<XLogTestPage> createState() => _XLogTestPageState();
}

class _XLogTestPageState extends State<XLogTestPage> {
  XLog? _xlog;
  XLogInstance? _instance;
  final List<String> _logs = [];
  XLogLevel _selectedLevel = XLogLevel.debug;
  int _logCounter = 0;

  void _addLog(String msg) {
    setState(() {
      _logs.insert(0, '[${DateTime.now().toString().substring(11, 19)}] $msg');
      if (_logs.length > 100) _logs.removeLast();
    });
  }

  Future<void> _openInstance() async {
    try {
      _xlog ??= XLog.initialize();
      final dir = await getApplicationDocumentsDirectory();
      final logdir = '${dir.path}${Platform.pathSeparator}xlog_test';
      await Directory(logdir).create(recursive: true);

      final config = XLogConfig(
        logdir: logdir,
        nameprefix: 'flutter_test',
        mode: XLogAppenderMode.async_,
        compressMode: XLogCompressMode.zstd,
      );

      _instance = _xlog!.open(config, level: _selectedLevel);
      _instance!.consoleLogOpen = true;
      _addLog('Instance opened: ptr=0x${_instance!._ptr.toRadixString(16)}, '
          'logdir=$logdir');
    } catch (e) {
      _addLog('ERROR: $e');
    }
  }

  void _closeInstance() {
    if (_instance == null) {
      _addLog('No instance to close');
      return;
    }
    _xlog!.release(_instance!.nameprefix);
    _addLog('Instance released: ${_instance!.nameprefix}');
    final exists = _xlog!.has(_instance!.nameprefix);
    _addLog('Has instance after release: $exists');
    _instance = null;
  }

  void _writeLog(XLogLevel level) {
    if (_instance == null || !_instance!.isValid) {
      _addLog('No valid instance');
      return;
    }
    _logCounter++;
    final msg = 'Test log #$_logCounter at level ${level.name}';
    switch (level) {
      case XLogLevel.verbose:
        _instance!.verbose('FlutterTest', msg);
      case XLogLevel.debug:
        _instance!.debug('FlutterTest', msg);
      case XLogLevel.info:
        _instance!.info('FlutterTest', msg);
      case XLogLevel.warn:
        _instance!.warn('FlutterTest', msg);
      case XLogLevel.error:
        _instance!.error('FlutterTest', msg);
      case XLogLevel.fatal:
        _instance!.fatal('FlutterTest', msg);
      default:
        break;
    }
    _addLog('Wrote: $msg');
  }

  void _flush({bool sync = false}) {
    if (_instance == null) {
      _addLog('No instance');
      return;
    }
    _instance!.flush(sync: sync);
    _addLog('Flushed (sync=$sync)');
  }

  void _flushAll() {
    _xlog?.flushAll(sync: true);
    _addLog('Flushed all (sync)');
  }

  void _getLogPath() {
    if (_instance == null) {
      _addLog('No instance');
      return;
    }
    final path = _instance!.logPath;
    _addLog('Log path: ${path ?? "N/A"}');
  }

  void _setLevel(XLogLevel level) {
    if (_instance == null) {
      _addLog('No instance');
      return;
    }
    _instance!.level = level;
    _addLog('Level set to ${level.name}');
    final enabled = _instance!.isEnabledFor(XLogLevel.debug);
    _addLog('Debug enabled: $enabled');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('XLog Flutter Test')),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Instance controls
            Wrap(spacing: 8, runSpacing: 8, children: [
              ElevatedButton(
                  onPressed: _openInstance, child: const Text('Open Instance')),
              ElevatedButton(
                  onPressed: _closeInstance,
                  child: const Text('Close Instance')),
            ]),
            const SizedBox(height: 8),

            // Level selector
            Row(children: [
              const Text('Level: '),
              DropdownButton<XLogLevel>(
                value: _selectedLevel,
                items: [
                  XLogLevel.verbose,
                  XLogLevel.debug,
                  XLogLevel.info,
                  XLogLevel.warn,
                  XLogLevel.error,
                  XLogLevel.fatal,
                ]
                    .map((l) =>
                        DropdownMenuItem(value: l, child: Text(l.name)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) {
                    setState(() => _selectedLevel = v);
                    _setLevel(v);
                  }
                },
              ),
            ]),
            const SizedBox(height: 8),

            // Write buttons
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final level in [
                XLogLevel.verbose,
                XLogLevel.debug,
                XLogLevel.info,
                XLogLevel.warn,
                XLogLevel.error,
                XLogLevel.fatal,
              ])
                ElevatedButton(
                  onPressed: () => _writeLog(level),
                  child: Text('Write ${level.name}'),
                ),
            ]),
            const SizedBox(height: 8),

            // Flush + utility
            Wrap(spacing: 8, runSpacing: 8, children: [
              ElevatedButton(
                  onPressed: () => _flush(), child: const Text('Flush')),
              ElevatedButton(
                  onPressed: () => _flush(sync: true),
                  child: const Text('Flush Sync')),
              ElevatedButton(
                  onPressed: _flushAll, child: const Text('Flush All')),
              ElevatedButton(
                  onPressed: _getLogPath, child: const Text('Get Log Path')),
            ]),
            const SizedBox(height: 12),

            // Status log
            const Text('Status Log:',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: ListView.builder(
                  itemCount: _logs.length,
                  itemBuilder: (_, i) => Text(_logs[i],
                      style: const TextStyle(
                          fontSize: 12, fontFamily: 'monospace')),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

**Note:** The `_instance!._ptr` field is private. You'll need to either:
- Add a public getter `int get pointer => _ptr;` to `XLogInstance`
- Or change `_ptr` to `ptr` (public)

Choose the public getter approach: add `int get pointer => _ptr;` to `XLogInstance` in `xlog.dart`, then use `_instance!.pointer.toRadixString(16)` in the example.

- [ ] **Step 3: Run the example on Windows**

```bash
cd samples/xlog_flutter/example
flutter run -d windows
```

Expected: App launches, no crash.

- [ ] **Step 4: Manual verification**

1. Click "Open Instance" -> Status shows non-zero pointer and logdir
2. Click "Write Info" several times -> Status shows writes
3. Click "Flush Sync" -> Status shows flushed
4. Click "Get Log Path" -> Status shows a valid file path
5. Check the logdir for `.xlog` files: `ls %USERPROFILE%\Documents\xlog_test\`
6. Click "Close Instance" -> Status shows released, has=false
7. Click "Write Info" again -> Status shows "No valid instance" (no crash)

- [ ] **Step 5: Commit**

```bash
git add samples/xlog_flutter/example/
git commit -m "feat(xlog_flutter): implement example app for Windows verification"
```

### Task 10: Final cleanup and commit

- [ ] **Step 1: Clean up any remaining template files**

Remove files generated by `flutter create` that are no longer needed, such as:
- Template C source files in `src/` (e.g., `xlog_flutter.c` or similar)
- Template Dart files that were replaced

- [ ] **Step 2: Verify `dart analyze` passes**

```bash
cd samples/xlog_flutter
dart analyze
```

Expected: No errors. Warnings are acceptable.

- [ ] **Step 3: Final commit**

```bash
git add -A samples/xlog_flutter/
git commit -m "chore(xlog_flutter): clean up template boilerplate"
```
