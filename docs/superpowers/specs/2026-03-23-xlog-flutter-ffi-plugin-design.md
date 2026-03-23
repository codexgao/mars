# xlog_flutter FFI Plugin Design

## Overview

Create a Flutter FFI plugin (`xlog_flutter`) that wraps the mars xlog multi-instance logging library. The plugin enables Flutter apps to use xlog for high-performance structured logging across all major platforms.

**Scope**: Architecture designed for iOS / Android / Windows / macOS / Linux. Current implementation phase covers Windows only, with other platforms as placeholders.

**Repository location**: `samples/xlog_flutter/`

## Architecture

```
┌──────────────────────────────────────────────────────┐
│  Flutter App (Dart)                                  │
│                                                      │
│  ┌────────────────────────────────────────────────┐  │
│  │  xlog.dart  (XLog / XLogInstance)              │  │
│  │  High-level Dart API                           │  │
│  └──────────────────┬─────────────────────────────┘  │
│                     │                                │
│  ┌──────────────────▼─────────────────────────────┐  │
│  │  xlog_bindings.dart  (ffigen generated)        │  │
│  │  1:1 FFI bindings to xlog_capi.h              │  │
│  └──────────────────┬─────────────────────────────┘  │
│                     │ dart:ffi                       │
├─────────────────────┼────────────────────────────────┤
│  Native (per-platform)                               │
│                     │                                │
│  ┌──────────────────▼─────────────────────────────┐  │
│  │  xlog_capi.h / xlog_capi.cc                   │  │
│  │  C ABI wrapper (extern "C")                    │  │
│  │  Compiled into xlog shared library             │  │
│  └──────────────────┬─────────────────────────────┘  │
│                     │                                │
│  ┌──────────────────▼─────────────────────────────┐  │
│  │  mars::xlog C++ multi-instance API             │  │
│  │  (xlogger_interface.h)                         │  │
│  └────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────┘
```

## Part 1: C API Layer (`mars/xlog/capi/`)

### Design Principles

- All functions `extern "C"` with platform export macro, guaranteed C ABI.
- Parameters use only C primitive types: `const char*`, `int`, `uintptr_t`, `bool`.
- String output uses caller-provided buffer + length.
- Errors expressed through return values (`0`/`NULL` = failure).
- Header is self-contained, no C++ dependencies.

### Files

```
mars/xlog/capi/
├── xlog_capi.h       # Pure C header, cross-platform
└── xlog_capi.cc      # Implementation: wraps C++ multi-instance API
```

### `xlog_capi.h` Interface

```c
#ifndef MARS_XLOG_CAPI_H_
#define MARS_XLOG_CAPI_H_

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Platform export macro */
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

/* Enumerations */
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

/* Configuration (pure C, fixed layout) */
typedef struct {
    xlog_appender_mode_t  mode;
    const char*           logdir;           /* required */
    const char*           nameprefix;       /* required */
    const char*           pub_key;          /* optional, NULL = no encryption */
    xlog_compress_mode_t  compress_mode;
    int                   compress_level;   /* 0-9 */
    const char*           cachedir;         /* optional, NULL = disabled */
    int                   cache_days;       /* 0 = unlimited */
} xlog_config_t;

/* ---- Instance lifecycle ---- */
XLOG_API uintptr_t  xlog_new_instance(const xlog_config_t* config, xlog_level_t level);
XLOG_API uintptr_t  xlog_get_instance(const char* nameprefix);
XLOG_API int        xlog_has_instance(const char* nameprefix);
XLOG_API void       xlog_release_instance(const char* nameprefix);
XLOG_API void       xlog_destroy_instance(uintptr_t instance);

/* ---- Log writing ---- */
XLOG_API void xlog_write(uintptr_t instance, xlog_level_t level,
                          const char* tag, const char* filename,
                          const char* funcname, int line,
                          const char* log);

/* ---- Log level ---- */
XLOG_API int          xlog_is_enabled_for(uintptr_t instance, xlog_level_t level);
XLOG_API xlog_level_t xlog_get_level(uintptr_t instance);
XLOG_API void         xlog_set_level(uintptr_t instance, xlog_level_t level);

/* ---- Control ---- */
XLOG_API void xlog_set_appender_mode(uintptr_t instance, xlog_appender_mode_t mode);
XLOG_API void xlog_set_console_log_open(uintptr_t instance, int is_open);
XLOG_API void xlog_flush(uintptr_t instance, int is_sync);
XLOG_API void xlog_flush_all(int is_sync);

/* ---- Path query ---- */
XLOG_API int xlog_get_log_path(uintptr_t instance, char* buf, unsigned int buf_len);

#ifdef __cplusplus
}
#endif

#endif /* MARS_XLOG_CAPI_H_ */
```

### `xlog_capi.cc` Implementation Notes

- `xlog_new_instance`: Constructs `XLogConfig` from C struct fields, calls `NewXloggerInstance`.
- `xlog_write`: Constructs `XLoggerInfo` (fills `timeval`/`pid`/`tid` internally), calls `XloggerWrite`.
- All `const char*` parameters: NULL-checked, treated as empty string if NULL.
- Compiled with `XLOG_CAPI_EXPORT` defined, enabling `dllexport` path.

### CMakeLists_dll.txt Changes

Add capi source files to the DLL build:

```cmake
file(GLOB XLOG_CAPI_FILES
    ${XLOG_ROOT}/capi/*.cc
    ${XLOG_ROOT}/capi/*.h
)
set(ALL_XLOG_SRC ${XLOG_SRC_FILES} ${XLOG_CRYPT_FILES} ${XLOG_CAPI_FILES})

target_compile_definitions(xlog_dll PRIVATE XLOG_CAPI_EXPORT)
```

### Header Export

`xlog_capi.h` added to `mars_utils.py` `XLOG_COPY_HEADER_FILES` so it exports to `build/windows/include/xlog/xlog_capi.h`. Consumers (Dart FFI or native C/C++) use this header.

## Part 2: Dart FFI Layer

### FFI Bindings Generation

Use `package:ffigen` to auto-generate `lib/src/xlog_bindings.dart` from `xlog_capi.h`.

**`ffigen.yaml`**:

```yaml
name: XLogBindings
description: FFI bindings for xlog C API
output: 'lib/src/xlog_bindings.dart'
headers:
  entry-points:
    - '../../mars/xlog/capi/xlog_capi.h'
  include-directives:
    - '**xlog_capi.h'
preamble: |
  // AUTO GENERATED - DO NOT EDIT
  // Generated by `dart run ffigen`
comments:
  style: any
  length: full
```

Generated file is committed to VCS so consumers do not need LLVM installed.

### High-Level Dart API (`xlog.dart`)

**`XLogConfig`**: Dart configuration class with named parameters. Maps to `xlog_config_t` for FFI calls.

**`XLogInstance`**: Wraps a `uintptr_t` handle. Provides convenience methods:
- `verbose()`, `debug()`, `info()`, `warn()`, `error()`, `fatal()` — write at specific level
- `isEnabledFor(level)` — check if level is active
- `level` getter/setter — current log level
- `appenderMode` setter — async/sync mode
- `consoleLogOpen` setter — toggle console output
- `flush({bool sync})` — flush this instance
- `logPath` getter — current log file path

**`XLog`** (singleton manager):
- `initialize()` — load native library per platform:
  - Windows: `DynamicLibrary.open('xlog.dll')`
  - macOS: `DynamicLibrary.open('libxlog.dylib')`
  - Linux: `DynamicLibrary.open('libxlog.so')`
  - iOS: `DynamicLibrary.process()` (static linking)
  - Android: `DynamicLibrary.open('libxlog.so')`
  - Unsupported: throws `UnsupportedError`
- `open(XLogConfig)` — create instance, returns `XLogInstance`
- `get(nameprefix)` — get existing instance
- `has(nameprefix)` — check existence
- `release(nameprefix)` — release instance
- `flushAll({bool sync})` — flush all instances

**Memory management**: All `Pointer<Utf8>` allocated for FFI calls are freed in `try/finally` blocks.

**Thread safety**: xlog C++ layer is thread-safe internally. Dart FFI calls are synchronous and do not require additional locking.

**Caller stack info**: `filename`/`line` parameters are optional in the Dart API. Parsing `StackTrace.current` is expensive; default is empty string (C layer receives "").

## Part 3: Flutter Plugin Structure

### Project Creation

```bash
flutter create --template=plugin_ffi \
  --org com.codexgao \
  --platforms=windows,linux,macos,ios,android \
  xlog_flutter
```

Then modify the generated skeleton.

### Key Modifications to Skeleton

1. Add `ffigen.yaml` at project root
2. Replace `lib/src/` with `xlog_bindings.dart` (generated) + `xlog.dart` (hand-written)
3. Replace `windows/CMakeLists.txt` to reference prebuilt xlog.dll
4. Update `example/lib/main.dart` with xlog verification UI
5. Clean up template boilerplate

### Windows Platform Integration (`windows/CMakeLists.txt`)

```cmake
cmake_minimum_required(VERSION 3.14)
project(xlog_flutter_plugin LANGUAGES C CXX)

set(XLOG_PREBUILT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../../mars/xlog/build/windows")

# Imported shared library (prebuilt, not compiled here)
add_library(xlog_flutter SHARED IMPORTED GLOBAL)
set_target_properties(xlog_flutter PROPERTIES
  IMPORTED_IMPLIB "${XLOG_PREBUILT_DIR}/Release/xlog.lib"
  IMPORTED_LOCATION "${XLOG_PREBUILT_DIR}/Release/xlog.dll"
)

# Install DLL to Flutter bundle
install(FILES "${XLOG_PREBUILT_DIR}/Release/xlog.dll"
  DESTINATION "${CMAKE_INSTALL_PREFIX}"
)

# Expose headers for native consumers
target_include_directories(xlog_flutter INTERFACE
  "${XLOG_PREBUILT_DIR}/include"
)
```

Native consumers in the host app can link against `xlog_flutter` and `#include "xlog/xlog_capi.h"`.

### Other Platforms (Placeholder)

linux, macos, ios, android platform directories contain placeholder files with TODO comments describing required prebuilt artifacts. Dart layer throws `UnsupportedError` on unsupported platforms during `XLog.initialize()`.

## Part 4: Example App & Verification

### UI Layout

Single-page app with buttons for each xlog operation:

- **Open Instance** / **Close Instance** — lifecycle
- **Level selector** — dropdown to set log level
- **Write buttons** — one per level (Verbose through Fatal)
- **Flush** / **Flush Sync** / **Flush All** — flush controls
- **Toggle Console** / **Get Log Path** — utility
- **Status bar** — shows instance pointer, current state, log path

### Verification Matrix

| Operation | C API | Success Criteria |
|-----------|-------|-----------------|
| Open Instance | `xlog_new_instance` | Returns non-zero handle |
| Write (each level) | `xlog_write` | `.xlog` file appears in logdir |
| Flush Sync | `xlog_flush` (sync=1) | File written immediately |
| Toggle Console | `xlog_set_console_log_open` | Logs appear in debug console |
| Get Log Path | `xlog_get_log_path` | Returns valid path string |
| Set Level | `xlog_set_level` + `xlog_is_enabled_for` | Filtered levels not written |
| Close Instance | `xlog_release_instance` | No crash, subsequent ops handled gracefully |

### Acceptance Criteria

1. `flutter run -d windows` launches without crash.
2. "Open Instance" returns non-zero handle.
3. After writing logs and flushing, `.xlog` files exist in configured `logdir`.
4. Console toggle produces visible output in debug console.
5. "Close Instance" followed by any operation does not crash.
6. Log files are decodable by mars xlog decode tools.

### Unit Tests (`test/xlog_test.dart`)

- DLL loads without exception
- `xlog_new_instance` returns non-zero
- `xlog_has_instance` returns true after creation
- `xlog_write` does not crash
- `xlog_flush` does not crash
- `xlog_release_instance` causes `xlog_has_instance` to return false

## Implementation Order

1. Create C API layer (`mars/xlog/capi/`) and rebuild xlog.dll
2. `flutter create` plugin skeleton
3. Configure ffigen, generate bindings
4. Implement `xlog.dart` high-level API
5. Configure `windows/CMakeLists.txt` for prebuilt DLL
6. Implement example app
7. Run verification on Windows
