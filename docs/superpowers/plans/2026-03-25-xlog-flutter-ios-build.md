# xlog Flutter iOS Build Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `mars/xlog` as an XCFramework (device arm64 + simulator x86_64+arm64) and wire it into the `samples/xlog_flutter` Flutter FFI plugin so the plugin runs on iOS.

**Architecture:** A Python build script (`build_ios.py`) drives three separate CMake builds (device-arm64, sim-x86_64, sim-arm64), merges the two simulator `.a` files with `libtool`, then assembles all slices into an XCFramework with `xcodebuild -create-xcframework`. The Flutter plugin podspec is updated to consume the prebuilt XCFramework.

**Tech Stack:** Python 3, CMake (Unix Makefiles / Xcode toolchain), libtool, xcodebuild, CocoaPods (podspec)

**Spec:** `docs/superpowers/specs/2026-03-25-xlog-flutter-ios-build-design.md`

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `mars/xlog/CMakeLists_ios.txt` | Create | CMake config for one iOS static library slice |
| `mars/xlog/build_ios.py` | Create | Orchestration: env check → cmake × 3 → libtool → xcframework |
| `samples/xlog_flutter/ios/xlog_flutter.podspec` | Modify | Reference prebuilt XCFramework |
| `samples/xlog_flutter/ios/Classes/xlog_flutter.c` | Modify | Replace broken include with stub |

---

## Key Context

**Repo root:** `/path/to/mars/` (SCRIPT_PATH is `mars/xlog/`, MARS_PATH is `mars/`)

**Reference files to read before coding:**
- `mars/xlog/build_macos.py` — mirror this structure
- `mars/xlog/CMakeLists_macos.txt` — mirror this structure
- `mars/mars_utils.py` — provides `clean`, `gen_mars_revision_file`, `libtool_libs`

**iOS OpenSSL:** `mars/openssl/openssl_lib_iOS/libcrypto.a` + `libssl.a`
- These are fat binaries containing `x86_64` and `arm64`.
- The `arm64` slice covers both device AND simulator arm64 (the prebuilt libs are not differentiated — this is fine for linking; any arm64-related mismatch is handled by CMake's sysroot selection).

**Three compilation targets:**

| Key | `CMAKE_OSX_SYSROOT` | `CMAKE_OSX_ARCHITECTURES` | Purpose |
|-----|---------------------|--------------------------|---------|
| `device` | `iphoneos` | `arm64` | Real device |
| `sim_x86` | `iphonesimulator` | `x86_64` | Intel Mac simulator |
| `sim_arm64` | `iphonesimulator` | `arm64` | Apple Silicon simulator |

Simulator `.a` files are merged with `libtool -static` → `libxlog_sim.a`  
Final xcframework has two slices: device `libxlog.a` + simulator `libxlog_sim.a`

**Default output path:** `<repo_root>/samples/xlog_flutter/ios/libs/`

---

## Task 1: Create CMakeLists_ios.txt

**Files:**
- Create: `mars/xlog/CMakeLists_ios.txt`

This file is nearly identical to `CMakeLists_macos.txt` with three changes:
1. Output is a STATIC library (`xlog_ios`) instead of SHARED
2. OpenSSL path uses `openssl_lib_iOS` instead of `openssl_lib_osx`
3. `CMAKE_OSX_DEPLOYMENT_TARGET` set to `12.0`
4. No `INSTALL_NAME_DIR` / `MACHO_COMPATIBILITY_VERSION` (not applicable to static libs)

- [ ] **Step 1: Create `mars/xlog/CMakeLists_ios.txt`**

```cmake
cmake_minimum_required(VERSION 3.10)
project(xlog_ios_build)

set(CMAKE_INSTALL_PREFIX "${CMAKE_BINARY_DIR}" CACHE PATH "Installation directory" FORCE)
message(STATUS "CMAKE_INSTALL_PREFIX=${CMAKE_INSTALL_PREFIX}")

# XLOG_SOURCE_DIR is passed in by build_ios.py via -DXLOG_SOURCE_DIR=...
if(NOT DEFINED XLOG_SOURCE_DIR)
    set(XLOG_SOURCE_DIR "${CMAKE_CURRENT_LIST_DIR}")
endif()
get_filename_component(MARS_ROOT "${XLOG_SOURCE_DIR}/.." ABSOLUTE)
set(XLOG_ROOT "${XLOG_SOURCE_DIR}")

# ---- Deployment target (must be set before project() takes effect for toolchain) ----
set(CMAKE_OSX_DEPLOYMENT_TARGET "12.0" CACHE STRING "" FORCE)

# ---- C++ standard ----
set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -stdlib=libc++")

# ---- Include directories ----
include_directories(${MARS_ROOT}/openssl/include)
include_directories(${XLOG_ROOT})
include_directories(${XLOG_ROOT}/src)
include_directories(${MARS_ROOT})
include_directories(${MARS_ROOT}/..)
include_directories(${MARS_ROOT}/comm)
include_directories(${MARS_ROOT}/comm/xlogger)
include_directories(${MARS_ROOT}/crypt)
include_directories(${MARS_ROOT}/crypt/micro-ecc-master)

# ---- Dependencies: comm / boost / zstd (statically linked) ----
add_subdirectory(${MARS_ROOT}/comm ${CMAKE_BINARY_DIR}/comm)
add_subdirectory(${MARS_ROOT}/boost ${CMAKE_BINARY_DIR}/boost)

option(ZSTD_BUILD_STATIC "BUILD STATIC LIBRARIES" ON)
option(ZSTD_BUILD_SHARED "BUILD SHARED LIBRARIES" OFF)
set(ZSTD_SOURCE_DIR "${MARS_ROOT}/zstd")
set(LIBRARY_DIR "${ZSTD_SOURCE_DIR}/lib")
include(GNUInstallDirs)
add_subdirectory(${MARS_ROOT}/zstd/build/cmake/lib ${CMAKE_BINARY_DIR}/zstd)

# ---- xlog source files ----
file(GLOB XLOG_SRC_FILES
    ${XLOG_ROOT}/src/*.cc
    ${XLOG_ROOT}/src/*.h
)
list(FILTER XLOG_SRC_FILES EXCLUDE REGEX ".*_unittest\\.cc$")
list(FILTER XLOG_SRC_FILES EXCLUDE REGEX ".*_mock\\.cc$")

file(GLOB XLOG_CRYPT_FILES
    ${XLOG_ROOT}/crypt/*.cc
    ${XLOG_ROOT}/crypt/*.h
    ${XLOG_ROOT}/crypt/micro-ecc-master/*.c
    ${XLOG_ROOT}/crypt/micro-ecc-master/*.h
)

file(GLOB XLOG_CAPI_FILES
    ${XLOG_ROOT}/capi/*.cc
    ${XLOG_ROOT}/capi/*.h
)

# Apple platform requires objc/*.mm sources
file(GLOB XLOG_OBJC_FILES
    ${XLOG_ROOT}/objc/*.mm
)

set(ALL_XLOG_SRC
    ${XLOG_SRC_FILES}
    ${XLOG_CRYPT_FILES}
    ${XLOG_CAPI_FILES}
    ${XLOG_OBJC_FILES}
)

# ---- Build as STATIC library ----
add_library(xlog_ios STATIC ${ALL_XLOG_SRC})

set_target_properties(xlog_ios PROPERTIES
    OUTPUT_NAME "xlog"
)

# Enable C API export macro
target_compile_definitions(xlog_ios PRIVATE XLOG_CAPI_EXPORT)

# ---- OpenSSL (prebuilt universal binary for iOS) ----
set(OPENSSL_LIB_DIR "${MARS_ROOT}/openssl/openssl_lib_iOS")
set(OPENSSL_CRYPTO_LIB "${OPENSSL_LIB_DIR}/libcrypto.a")
set(OPENSSL_SSL_LIB    "${OPENSSL_LIB_DIR}/libssl.a")
if(NOT EXISTS "${OPENSSL_CRYPTO_LIB}")
    message(FATAL_ERROR "libcrypto.a not found in ${OPENSSL_LIB_DIR}")
endif()
if(NOT EXISTS "${OPENSSL_SSL_LIB}")
    message(FATAL_ERROR "libssl.a not found in ${OPENSSL_LIB_DIR}")
endif()
message(STATUS "OpenSSL crypto: ${OPENSSL_CRYPTO_LIB}")
message(STATUS "OpenSSL ssl:    ${OPENSSL_SSL_LIB}")

# ---- Link ----
target_link_libraries(xlog_ios
    comm
    mars-boost
    libzstd_static
    ${OPENSSL_CRYPTO_LIB}
    ${OPENSSL_SSL_LIB}
    "-framework Foundation"
    "-framework CoreFoundation"
    z        # system zlib
)
```

- [ ] **Step 2: Verify the file was created**

```bash
ls -la mars/xlog/CMakeLists_ios.txt
```

Expected: file exists, ~80 lines

- [ ] **Step 3: Commit**

```bash
git add mars/xlog/CMakeLists_ios.txt
git commit -m "build(ios): add CMakeLists_ios.txt for iOS static library"
```

---

## Task 2: Create build_ios.py

**Files:**
- Create: `mars/xlog/build_ios.py`

This script orchestrates the full build. It is modeled directly on `build_macos.py`. Key differences:
- Three targets instead of two (`device`, `sim_x86`, `sim_arm64`)
- Passes `-DCMAKE_OSX_SYSROOT=iphoneos` or `-DCMAKE_OSX_SYSROOT=iphonesimulator`
- After compilation, uses `libtool -static` (not lipo) to merge simulator `.a` files
- Uses `xcodebuild -create-xcframework` to assemble final xcframework
- Default output: `<repo_root>/samples/xlog_flutter/ios/libs/`

- [ ] **Step 1: Create `mars/xlog/build_ios.py`**

```python
#!/usr/bin/env python3
"""
Build script for xlog iOS XCFramework.

Compiles the xlog module (and its dependencies: comm, boost, zstd) into an
iOS XCFramework containing:
  - Device slice:    arm64           (iphoneos)
  - Simulator slice: x86_64 + arm64  (iphonesimulator)

Outputs libxlog.xcframework to the configured output directory.

Usage:
    python build_ios.py --config Release
    python build_ios.py --config Debug
    python build_ios.py --config Release --incremental
    python build_ios.py --config Release --output-dir /path/to/output
"""

import os
import sys
import glob
import time
import shutil
import platform
import argparse
import subprocess
from typing import Optional

# ---- Path Setup ----

SCRIPT_PATH: str = os.path.dirname(os.path.realpath(__file__))
MARS_PATH: str = os.path.normpath(os.path.join(SCRIPT_PATH, '..'))

# Add mars/ directory to sys.path so we can import mars_utils
sys.path.insert(0, MARS_PATH)
from mars_utils import (
    clean,
    libtool_libs,
    gen_mars_revision_file,
)

# ---- Constants ----

CMAKE_LISTS_FILE: str = os.path.join(SCRIPT_PATH, 'CMakeLists_ios.txt')
DEPLOYMENT_TARGET: str = '12.0'

# Three compilation targets: (key, sysroot, arch)
IOS_TARGETS = [
    ('device',   'iphoneos',      'arm64'),
    ('sim_x86',  'iphonesimulator', 'x86_64'),
    ('sim_arm64','iphonesimulator', 'arm64'),
]


# ---- Environment Check ----

def check_environment() -> bool:
    """Check that iOS build environment is ready."""
    if platform.system() != 'Darwin':
        print('Error: build_ios.py must be run on macOS.')
        return False

    if shutil.which('cmake') is None:
        print('Error: cmake not found. Install via: brew install cmake')
        return False

    ret = subprocess.call(
        ['xcode-select', '-p'],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    if ret != 0:
        print('Error: Xcode Command Line Tools not installed.')
        print('  Install via: xcode-select --install')
        return False

    if shutil.which('xcodebuild') is None:
        print('Error: xcodebuild not found. Install Xcode from the App Store.')
        return False

    if not os.path.isfile(CMAKE_LISTS_FILE):
        print(f'Error: CMakeLists_ios.txt not found at {CMAKE_LISTS_FILE}')
        return False

    return True


# ---- CMake Steps ----

def cmake_generate(build_dir: str, sysroot: str, arch: str, config: str) -> bool:
    """Run CMake configure/generate step for a single target."""
    os.makedirs(build_dir, exist_ok=True)

    # Copy CMakeLists_ios.txt into build dir as CMakeLists.txt
    wrapper_path: str = os.path.join(build_dir, 'CMakeLists.txt')
    shutil.copy2(CMAKE_LISTS_FILE, wrapper_path)

    cmake_cmd: str = (
        f'cmake "{build_dir}" '
        f'-G "Unix Makefiles" '
        f'-DCMAKE_BUILD_TYPE={config} '
        f'-DCMAKE_OSX_SYSROOT={sysroot} '
        f'-DCMAKE_OSX_ARCHITECTURES={arch} '
        f'-DCMAKE_OSX_DEPLOYMENT_TARGET={DEPLOYMENT_TARGET} '
        f'-DXLOG_SOURCE_DIR="{SCRIPT_PATH.replace(os.sep, "/")}"'
    )
    print(f'[cmake generate/{arch}/{sysroot}] {cmake_cmd}')
    ret: int = subprocess.call(cmake_cmd, cwd=build_dir, shell=True)
    return ret == 0


def cmake_build(build_dir: str, config: str, target_key: str) -> bool:
    """Run CMake build step."""
    cpu_count = os.cpu_count() or 4
    cmake_cmd: str = (
        f'cmake --build "{build_dir}" '
        f'--target xlog_ios '
        f'--config {config} '
        f'-- -j{cpu_count}'
    )
    print(f'[cmake build/{target_key}] {cmake_cmd}')
    ret: int = subprocess.call(cmake_cmd, cwd=build_dir, shell=True)
    return ret == 0


# ---- Output Helpers ----

def find_static_lib(build_dir: str) -> Optional[str]:
    """Find the built libxlog.a in the build directory."""
    patterns = [
        os.path.join(build_dir, 'libxlog.a'),
        os.path.join(build_dir, '**', 'libxlog.a'),
    ]
    for pattern in patterns:
        matches = glob.glob(pattern, recursive=True)
        if matches:
            return matches[0]
    return None


def merge_simulator_libs(sim_x86_a: str, sim_arm64_a: str, out_a: str) -> bool:
    """
    Merge x86_64 and arm64 simulator static libraries into one fat archive.

    libtool -static is used (not lipo) because .a files are archives of
    object files, not single Mach-O binaries. libtool handles the merging
    of object file archives correctly.
    """
    os.makedirs(os.path.dirname(out_a), exist_ok=True)
    print(f'[libtool] Merging simulator libs:')
    print(f'  x86_64: {sim_x86_a}')
    print(f'  arm64:  {sim_arm64_a}')
    print(f'  output: {out_a}')
    return libtool_libs([sim_x86_a, sim_arm64_a], out_a)


def create_xcframework(device_a: str, simulator_a: str, output_xcframework: str) -> bool:
    """
    Use xcodebuild -create-xcframework to assemble the final XCFramework from
    the device and (merged) simulator static libraries.
    """
    # Remove existing xcframework first (xcodebuild will fail if it already exists)
    if os.path.exists(output_xcframework):
        shutil.rmtree(output_xcframework)

    xcf_cmd: str = (
        f'xcodebuild -create-xcframework '
        f'-library "{device_a}" '
        f'-library "{simulator_a}" '
        f'-output "{output_xcframework}"'
    )
    print(f'[xcframework] {xcf_cmd}')
    ret: int = subprocess.call(xcf_cmd, shell=True)
    if ret != 0:
        print('Error: xcodebuild -create-xcframework failed.')
        return False

    if not os.path.isdir(output_xcframework):
        print(f'Error: xcframework directory not found at {output_xcframework}')
        return False

    print(f'  XCFramework -> {output_xcframework}')
    return True


# ---- Main ----

def main() -> None:
    parser = argparse.ArgumentParser(
        description=(
            'Build xlog as an iOS XCFramework '
            '(device: arm64, simulator: x86_64 + arm64)'
        )
    )
    parser.add_argument(
        '--config',
        type=str,
        choices=['Release', 'Debug'],
        default='Release',
        help='Build configuration: Release or Debug (default: Release)',
    )
    parser.add_argument(
        '--incremental',
        action='store_true',
        default=False,
        help='Incremental build (skip cleaning the build directories)',
    )
    parser.add_argument(
        '--output-dir',
        type=str,
        default=None,
        help='Output directory (default: <repo_root>/samples/xlog_flutter/ios/libs)',
    )
    args = parser.parse_args()

    config: str = args.config
    incremental: bool = args.incremental

    # Default output: samples/xlog_flutter/ios/libs (relative to repo root)
    repo_root: str = os.path.normpath(os.path.join(MARS_PATH, '..'))
    default_output: str = os.path.join(
        repo_root, 'samples', 'xlog_flutter', 'ios', 'libs'
    )
    output_dir: str = os.path.abspath(args.output_dir or default_output)

    # Per-target build temp directories
    build_base: str = os.path.join(SCRIPT_PATH, 'build')
    build_dirs = {
        key: os.path.join(build_base, f'cmake_tmp_ios_{key}')
        for key, _, _ in IOS_TARGETS
    }

    # Intermediate merged simulator lib
    sim_merge_dir: str = os.path.join(build_base, 'cmake_tmp_ios_sim_merged')
    sim_merged_a: str = os.path.join(sim_merge_dir, 'libxlog.a')

    # Final outputs
    config_output_dir: str = os.path.join(output_dir, config)
    output_xcframework: str = os.path.join(config_output_dir, 'libxlog.xcframework')

    print('========== xlog iOS XCFramework Build ==========')
    print(f'  Config:      {config}')
    print(f'  Incremental: {incremental}')
    print(f'  Output:      {output_dir}')
    print(f'  Targets:     {", ".join(k for k, _, _ in IOS_TARGETS)}')
    print()

    before_time: float = time.time()

    # Step 1: Check environment
    print('[1/6] Checking environment...')
    if not check_environment():
        sys.exit(1)

    # Step 2: Generate version info
    print('[2/6] Generating version info...')
    gen_mars_revision_file(os.path.join(MARS_PATH, 'comm'))

    # Step 3: Configure CMake for each target
    print('[3/6] Configuring CMake projects...')
    for key, sysroot, arch in IOS_TARGETS:
        build_dir = build_dirs[key]
        clean(build_dir, incremental)
        if not cmake_generate(build_dir, sysroot, arch, config):
            print(f'!!!!!!!!!!!!!!!!!!CMake generate failed for {key}!!!!!!!!!!!!!!!!!!!!')
            sys.exit(1)

    # Step 4: Build each target
    print(f'[4/6] Building xlog static libs ({config})...')
    built_libs: dict = {}
    for key, _, _ in IOS_TARGETS:
        build_dir = build_dirs[key]
        print(f'  Building {key}...')
        if not cmake_build(build_dir, config, key):
            print(f'!!!!!!!!!!!!!!!!!!Build failed for {key}!!!!!!!!!!!!!!!!!!!!')
            sys.exit(1)

        lib_path = find_static_lib(build_dir)
        if not lib_path or not os.path.isfile(lib_path):
            print(f'Error: libxlog.a not found after build for target={key}')
            sys.exit(1)
        built_libs[key] = lib_path
        print(f'  [{key}] {lib_path}')

    # Step 5: Merge simulator libs
    print('[5/6] Merging simulator architectures...')
    os.makedirs(sim_merge_dir, exist_ok=True)
    if not merge_simulator_libs(built_libs['sim_x86'], built_libs['sim_arm64'], sim_merged_a):
        print('!!!!!!!!!!!!!!!!!!Simulator lib merge failed!!!!!!!!!!!!!!!!!!!!')
        sys.exit(1)
    if not os.path.isfile(sim_merged_a):
        print(f'Error: merged simulator lib not found at {sim_merged_a}')
        sys.exit(1)

    # Step 6: Assemble XCFramework
    print('[6/6] Assembling XCFramework...')
    os.makedirs(config_output_dir, exist_ok=True)
    if not create_xcframework(built_libs['device'], sim_merged_a, output_xcframework):
        print('!!!!!!!!!!!!!!!!!!XCFramework assembly failed!!!!!!!!!!!!!!!!!!!!')
        sys.exit(1)

    after_time: float = time.time()

    print()
    print('==================== Build Complete ====================')
    print(f'  XCFramework: {output_xcframework}')
    print(f'  Time:        {int(after_time - before_time)}s')
    print()
    print('Verify with:')
    print(f'  xcodebuild -create-xcframework -help  # sanity check')
    print(f'  ls {output_xcframework}')
    print('========================================================')


if __name__ == '__main__':
    main()
```

- [ ] **Step 2: Verify the file was created**

```bash
python3 mars/xlog/build_ios.py --help
```

Expected: prints usage/help without errors

- [ ] **Step 3: Commit**

```bash
git add mars/xlog/build_ios.py
git commit -m "build(ios): add build_ios.py XCFramework build script"
```

---

## Task 3: Update podspec and Classes stub

**Files:**
- Modify: `samples/xlog_flutter/ios/xlog_flutter.podspec`
- Modify: `samples/xlog_flutter/ios/Classes/xlog_flutter.c`

- [ ] **Step 1: Replace `samples/xlog_flutter/ios/Classes/xlog_flutter.c`**

Replace the entire file contents with:

```c
// This file is intentionally left as a stub.
// The xlog library is provided as a prebuilt XCFramework
// (libs/Release/libxlog.xcframework).
// No source compilation is needed here.
```

- [ ] **Step 2: Replace `samples/xlog_flutter/ios/xlog_flutter.podspec`**

Replace the entire file contents with:

```ruby
#
# Run `pod lib lint xlog_flutter.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'xlog_flutter'
  s.version          = '0.0.1'
  s.summary          = 'Flutter FFI plugin for mars xlog (iOS).'
  s.description      = <<-DESC
Flutter FFI plugin for the mars xlog logging library. Uses a prebuilt
XCFramework covering iOS device (arm64) and simulator (x86_64 + arm64).
                       DESC
  s.homepage         = 'https://github.com/Tencent/mars'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Tencent' => 'mars@tencent.com' }

  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'

  # Prebuilt XCFramework (device arm64 + simulator x86_64+arm64).
  # Build it first with: python mars/xlog/build_ios.py --config Release
  s.vendored_frameworks = 'libs/Release/libxlog.xcframework'
  s.preserve_paths      = 'libs/**/*'

  s.dependency 'Flutter'
  s.platform = :ios, '12.0'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE'                        => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]'  => 'i386',
  }
  s.swift_version = '5.0'
end
```

- [ ] **Step 3: Verify no broken includes remain**

```bash
grep -r '#include.*src/xlog_flutter' samples/xlog_flutter/ios/
```

Expected: no output (grep finds nothing)

- [ ] **Step 4: Commit**

```bash
git add samples/xlog_flutter/ios/Classes/xlog_flutter.c \
        samples/xlog_flutter/ios/xlog_flutter.podspec
git commit -m "feat(ios): update podspec to consume prebuilt xcframework"
```

---

## Task 4: Smoke-test the build script

> Run only on macOS with Xcode installed. Requires cmake and xcodebuild.

- [ ] **Step 1: Run the build script**

```bash
python3 mars/xlog/build_ios.py --config Release
```

Expected: exits 0, prints "Build Complete", shows XCFramework path.

- [ ] **Step 2: Verify XCFramework structure**

```bash
ls samples/xlog_flutter/ios/libs/Release/libxlog.xcframework/
```

Expected output should contain slices like:
```
Info.plist
ios-arm64/
ios-arm64_x86_64-simulator/   (or similar)
```

- [ ] **Step 3: Verify architecture slices**

```bash
# Device slice
file samples/xlog_flutter/ios/libs/Release/libxlog.xcframework/ios-arm64/libxlog.a

# Simulator slice
file samples/xlog_flutter/ios/libs/Release/libxlog.xcframework/ios-arm64_x86_64-simulator/libxlog.a
```

Expected: each reports as `current ar archive random library`

- [ ] **Step 4: Verify symbols present**

```bash
nm samples/xlog_flutter/ios/libs/Release/libxlog.xcframework/ios-arm64/libxlog.a \
  | grep xlog_appender_open | head -5
```

Expected: one or more symbol lines containing `xlog_appender_open`

- [ ] **Step 5: Run incremental build**

```bash
python3 mars/xlog/build_ios.py --config Release --incremental
```

Expected: exits 0 (faster than full build)

- [ ] **Step 6: Commit xcframework if tests pass**

```bash
git add samples/xlog_flutter/ios/libs/
git commit -m "build(ios): add prebuilt libxlog.xcframework for Release"
```

---

## Task 5: Flutter integration test (optional, requires device/simulator)

> Skip if no iOS simulator is available in the current environment.

- [ ] **Step 1: Run pod install in example app**

```bash
cd samples/xlog_flutter/example/ios && pod install
```

Expected: CocoaPods resolves `xlog_flutter` podspec and links xcframework without errors.

- [ ] **Step 2: Build for simulator**

```bash
cd samples/xlog_flutter/example
flutter build ios --simulator
```

Expected: exits 0, no missing symbol linker errors.

- [ ] **Step 3: Run on simulator**

```bash
cd samples/xlog_flutter/example
flutter run -d iPhone
```

Expected: app launches, xlog initializes without crash.

---

## Notes

- The `libtool_libs` helper in `mars_utils.py` (line 114) calls `libtool -static -no_warning_for_no_symbols`. Use it directly — no need to shell out manually.
- The iOS OpenSSL fat binary already contains both `x86_64` and `arm64`. CMake will naturally pick the correct slice via the sysroot. No need to thin the fat binary before linking.
- If `xcodebuild -create-xcframework` reports a "same architectures" error, it means both the device and simulator `.a` files were compiled for `arm64` with the same sysroot — verify that `cmake_generate` passes the correct sysroot for each target.
