# Design: xlog Flutter iOS Build Support

**Date:** 2026-03-25
**Status:** Approved

## Overview

Add iOS build support to the `samples/xlog_flutter` Flutter FFI plugin. The goal is to compile
`mars/xlog` (plus its dependencies: comm, boost, zstd, OpenSSL) into an XCFramework that covers
all Apple target combinations, and update the plugin's podspec to consume it.

## Goals

- Produce `libxlog.xcframework` containing:
  - Device slice: `arm64` (sysroot: `iphoneos`)
  - Simulator slice: fat binary `x86_64 + arm64` (sysroot: `iphonesimulator`)
- Export `.dSYM` debug symbols for Release builds (for crash-symbol platforms such as Bugly / Crashlytics)
- Default output path: `samples/xlog_flutter/ios/libs/`
- Mirror the style and structure of the existing `build_macos.py` / `CMakeLists_macos.txt`

## Non-Goals

- tvOS / watchOS support
- Bitcode embedding (deprecated in Xcode 14+)
- CI/CD integration (out of scope for this spec)

---

## Files to Create or Modify

| File | Action |
|------|--------|
| `mars/xlog/CMakeLists_ios.txt` | **Create** — CMake config for iOS static library |
| `mars/xlog/build_ios.py` | **Create** — Build script |
| `samples/xlog_flutter/ios/xlog_flutter.podspec` | **Modify** — Reference xcframework |
| `samples/xlog_flutter/ios/Classes/xlog_flutter.c` | **Modify** — Replace broken include with stub |

---

## Part 1: CMakeLists_ios.txt

Closely mirrors `CMakeLists_macos.txt`. Key differences:

| Item | macOS | iOS |
|------|-------|-----|
| Library type | `SHARED` (dylib) | `STATIC` (.a) |
| Target name | `xlog_macos` | `xlog_ios` |
| OpenSSL path | `openssl_lib_osx` | `openssl_lib_iOS` |
| System Frameworks | Foundation, CoreFoundation | Foundation, CoreFoundation |
| `CMAKE_OSX_SYSROOT` | `macosx` | `iphoneos` or `iphonesimulator` (passed by build script) |

The CMake file accepts `XLOG_SOURCE_DIR` and `IOS_SYSROOT` as input variables (passed via
`-D` flags from the build script). `IOS_SYSROOT` is one of `iphoneos` or `iphonesimulator`.

Source files included (same as macOS):

```
xlog/src/*.cc
xlog/crypt/*.cc  +  crypt/micro-ecc-master/*.c
xlog/capi/*.cc
xlog/objc/*.mm        ← Apple-specific ObjC sources
```

Compiler flags added for iOS that differ from macOS:

```cmake
set(CMAKE_OSX_DEPLOYMENT_TARGET "12.0" CACHE STRING "" FORCE)
```

`CMAKE_OSX_SYSROOT` is passed by the build script via `-DCMAKE_OSX_SYSROOT=iphoneos` or
`-DCMAKE_OSX_SYSROOT=iphonesimulator`. See build_ios.py for details.

---

## Part 2: build_ios.py

### Build Steps (6 phases)

```
[1/6] 检查环境        → macOS + cmake + xcode-select + Xcode
[2/6] 生成版本信息    → gen_mars_revision_file()
[3/6] CMake 配置      → 3 个 arch 分别在独立 build_dir 中配置
[4/6] 编译            → 3 个 arch 分别编译 → libxlog.a
[5/6] 合并 Simulator  → libtool 合并 x86_64 + arm64-sim → libxlog_sim.a
[6/6] 打包 XCFramework → xcodebuild -create-xcframework
```

### Compilation Targets

| Target key | `CMAKE_OSX_SYSROOT` | `CMAKE_OSX_ARCHITECTURES` | XCFramework slice |
|------------|---------------------|--------------------------|-------------------|
| `device`   | `iphoneos`          | `arm64`                  | `ios-arm64` |
| `sim_x86`  | `iphonesimulator`   | `x86_64`                 | (merged first) |
| `sim_arm64`| `iphonesimulator`   | `arm64`                  | (merged first) |

The two simulator `.a` files are merged with `lipo` before being passed to
`xcodebuild -create-xcframework` as a single simulator slice.

### xcframework Assembly

```bash
# Merge simulator architectures (x86_64 + arm64-sim)
libtool -static -no_warning_for_no_symbols \
  -o <build>/simulator/libxlog.a \
  <build>/sim_x86/libxlog.a \
  <build>/sim_arm64/libxlog.a

# Create xcframework
xcodebuild -create-xcframework \
  -library <build>/device/libxlog.a     \
  -library <build>/simulator/libxlog.a  \
  -output  <output_dir>/Release/libxlog.xcframework
```

**Why libtool for static archives:** `lipo` is designed for Mach-O binaries (executables, dylibs).
For static `.a` archives (which are collections of object files), `libtool -static` is the
correct tool to merge multiple `.a` files from different architectures into a single universal
archive.

### dSYM Export (Release only)

**Important:** dSYM files cannot be directly extracted from static `.a` archives with `dsymutil`.
dSYM debug information is a feature of linked executables and dylibs, not static libraries.

For static library consumers, debug symbols are embedded in the object files within the `.a`.
Consumers must link the `.a` into their app binary; the resulting app binary will contain the
debug info and can be symbolicated by Crashlytics, Bugly, etc.

**For now:** No standalone dSYM export. Debug symbols are preserved in the `.a` files themselves.
In the future, if dSYM export becomes necessary, it can be generated from the final app binary
that links the xcframework (outside the scope of this build script).

### CLI Interface

```bash
python mars/xlog/build_ios.py --config Release
python mars/xlog/build_ios.py --config Debug
python mars/xlog/build_ios.py --config Release --incremental
python mars/xlog/build_ios.py --config Release --output-dir /custom/path
```

### Default Output Path

```
samples/xlog_flutter/ios/libs/
└── Release/
    └── libxlog.xcframework/       # device (arm64) + simulator (x86_64 + arm64)
```

The build script creates this directory automatically if it does not exist.

---

## Part 3: Podspec Update

Replace the generic template in `samples/xlog_flutter/ios/xlog_flutter.podspec`:

```ruby
Pod::Spec.new do |s|
  s.name             = 'xlog_flutter'
  s.version          = '0.0.1'
  s.summary          = 'Flutter FFI plugin for mars xlog (iOS).'
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'

  # Prebuilt XCFramework
  s.vendored_frameworks = 'libs/Release/libxlog.xcframework'
  s.preserve_paths      = 'libs/**/*'

  s.dependency 'Flutter'
  s.platform = :ios, '12.0'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE'                          => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]'    => 'i386',
  }
  s.swift_version = '5.0'
end
```

---

## Part 4: Classes/xlog_flutter.c Stub

Replace the broken `#include "../../src/xlog_flutter.c"` with a stub comment, matching the
macOS pattern:

```c
// This file is intentionally left as a stub.
// The xlog library is provided as a prebuilt XCFramework (libs/Release/libxlog.xcframework).
// No source compilation is needed here.
```

---

## iOS Deployment Target

`12.0` — consistent with the existing podspec template and broadly supported.

---

## Dependencies

| Dependency | Source | Notes |
|------------|--------|-------|
| comm | `mars/comm/` | Compiled from source, statically linked |
| boost | `mars/boost/` | Compiled from source, statically linked |
| zstd | `mars/zstd/build/cmake/lib/` | Compiled from source, statically linked |
| OpenSSL | `mars/openssl/openssl_lib_iOS/libcrypto.a` + `libssl.a` | Prebuilt universal `.a` |

---

## Error Handling

- **Environment:** Check for macOS, cmake, xcode-select, and Xcode installation upfront with actionable messages
- **CMake configure/build:** Each per-architecture configuration and build step is checked; script exits with code 1 on any failure
- **Output validation:** After each CMake build, validate that `libxlog.a` exists and is a valid static library
- **libtool merge:** Validate libtool return code before proceeding to xcframework assembly
- **xcframework assembly:** Validate `xcodebuild -create-xcframework` return code and check that the output directory structure is valid
- **File existence:** All intermediate and final output files are verified to exist before proceeding to the next step

---

## Testing Checklist

- [ ] Environment check: script rejects non-macOS platforms with clear error
- [ ] `python build_ios.py --config Release` completes without error
- [ ] `libtool` successfully merges simulator `.a` files (check return code and file size)
- [ ] `xcodebuild -create-xcframework` produces valid xcframework directory structure
- [ ] Verify xcframework content:
  ```bash
  file samples/xlog_flutter/ios/libs/Release/libxlog.xcframework/ios-arm64/libxlog.a
  file samples/xlog_flutter/ios/libs/Release/libxlog.xcframework/ios-arm64_x86_64-simulator/libxlog.a
  ```
- [ ] Verify symbols are present in both slices:
  ```bash
  nm samples/xlog_flutter/ios/libs/Release/libxlog.xcframework/ios-arm64/libxlog.a | grep xlog_appender
  ```
- [ ] CocoaPods can resolve xcframework: run `pod install` in example app
- [ ] Flutter example app builds for simulator: `flutter build ios --simulator`
- [ ] Flutter example app runs on simulator without missing symbol errors
- [ ] Flutter example app builds for physical device: `flutter build ios`
- [ ] Flutter example app runs on physical device without crashing on library load
- [ ] `python build_ios.py --config Debug` completes (no release-only features needed)
- [ ] `python build_ios.py --config Release --incremental` completes without full clean
