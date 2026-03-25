# xlog Flutter macOS 构建支持 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 `samples/xlog_flutter` 插件创建 macOS 预编译库构建支持，产出 `libxlog.dylib`（Universal Binary: arm64 + x86_64），使插件可以在 macOS 上正常运行。

**Architecture:** 新建 `CMakeLists_macos.txt` 定义 xlog macOS dylib 的最小构建（静态链接 comm/boost/zstd/OpenSSL，APPLE 分支使用 objc/*.mm），新建 `build_macos.py` 构建脚本分两架构编译再用 lipo 合并，更新 macOS Podspec 改用 `vendored_libraries` 引用预编译产物。

**Tech Stack:** Python 3, CMake, Apple Clang, lipo, CocoaPods

**Spec:** `docs/superpowers/specs/2026-03-25-xlog-flutter-macos-build-design.md`

---

## 背景说明

本计划实现分两架构编译 + lipo 合并的方法：

1. **为什么要分两架构编译？** macOS 设备同时支持 Intel (x86_64) 和 Apple Silicon (arm64)。通过 Universal Binary 可以在两类设备上无需重新编译就能运行。

2. **为什么不用 xcodebuild？** 因为 xlog 的 CMakeLists 针对 Unix 工具链，直接用 CMake 更简洁。Flutter 插件系统通过 CocoaPods 集成，CocoaPods 会自动处理 Xcode 集成细节。

3. **OpenSSL 库特性：** `mars/openssl/openssl_lib_osx/` 中的 .a 文件已预编译为 Universal Binary（x86_64 + arm64），所以构建时两个架构都能链接同一份 OpenSSL，无需分离。

---

## 文件清单

| 操作 | 文件 | 说明 |
|------|------|------|
| 新建 | `mars/xlog/CMakeLists_macos.txt` | xlog macOS dylib CMake 构建定义 |
| 新建 | `mars/xlog/build_macos.py` | macOS 构建脚本 |
| 修改 | `samples/xlog_flutter/macos/xlog_flutter.podspec` | 改用 vendored_libraries |
| 生成(提交) | `samples/xlog_flutter/macos/libs/Release/libxlog.dylib` | 预编译产物 |

---

## Task 1: 创建 CMakeLists_macos.txt

**Files:**
- Create: `mars/xlog/CMakeLists_macos.txt`

参照 `mars/xlog/CMakeLists_dll.txt` 结构，去除所有 Windows/MSVC 特定内容，加入 Apple 平台依赖和选项。

- [ ] **Step 1: 创建 CMakeLists_macos.txt**

创建 `mars/xlog/CMakeLists_macos.txt`，内容如下：

```cmake
cmake_minimum_required(VERSION 3.10)
project(xlog_macos_build)

set(CMAKE_INSTALL_PREFIX "${CMAKE_BINARY_DIR}" CACHE PATH "Installation directory" FORCE)
message(STATUS "CMAKE_INSTALL_PREFIX=${CMAKE_INSTALL_PREFIX}")

# XLOG_SOURCE_DIR 由构建脚本通过 -DXLOG_SOURCE_DIR=... 传入
if(NOT DEFINED XLOG_SOURCE_DIR)
    set(XLOG_SOURCE_DIR "${CMAKE_CURRENT_LIST_DIR}")
endif()
set(MARS_ROOT "${XLOG_SOURCE_DIR}/..")
set(XLOG_ROOT "${XLOG_SOURCE_DIR}")

# ---- 包含目录 ----
include_directories(${MARS_ROOT}/openssl/include)
include_directories(${XLOG_ROOT})
include_directories(${XLOG_ROOT}/src)
include_directories(${MARS_ROOT})
include_directories(${MARS_ROOT}/..)
include_directories(${MARS_ROOT}/comm)
include_directories(${MARS_ROOT}/comm/xlogger)
include_directories(${MARS_ROOT}/crypt)
include_directories(${MARS_ROOT}/crypt/micro-ecc-master)

# ---- 依赖：comm / boost / zstd（静态链接进 dylib）----
add_subdirectory(${MARS_ROOT}/comm ${CMAKE_BINARY_DIR}/comm)
add_subdirectory(${MARS_ROOT}/boost ${CMAKE_BINARY_DIR}/boost)

option(ZSTD_BUILD_STATIC "BUILD STATIC LIBRARIES" ON)
option(ZSTD_BUILD_SHARED "BUILD SHARED LIBRARIES" OFF)
set(ZSTD_SOURCE_DIR "${MARS_ROOT}/zstd")
set(LIBRARY_DIR ${ZSTD_SOURCE_DIR}/lib)
include(GNUInstallDirs)
add_subdirectory(${MARS_ROOT}/zstd/build/cmake/lib ${CMAKE_BINARY_DIR}/zstd)

# ---- xlog 源文件 ----

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

# Apple 平台需要 objc/*.mm
file(GLOB XLOG_OBJC_FILES
    ${XLOG_ROOT}/objc/*.mm
)

set(ALL_XLOG_SRC
    ${XLOG_SRC_FILES}
    ${XLOG_CRYPT_FILES}
    ${XLOG_CAPI_FILES}
    ${XLOG_OBJC_FILES}
)

# ---- 构建为 SHARED 库（dylib）----
add_library(xlog_macos SHARED ${ALL_XLOG_SRC})

set_target_properties(xlog_macos PROPERTIES
    OUTPUT_NAME "xlog"
    MACHO_COMPATIBILITY_VERSION 1.0.0
    MACHO_CURRENT_VERSION 1.0.0
    INSTALL_NAME_DIR "@rpath"
)

# 启用 C API 导出宏
target_compile_definitions(xlog_macos PRIVATE XLOG_CAPI_EXPORT)

# ---- OpenSSL（预编译 Universal Binary）----
set(OPENSSL_LIB_DIR "${MARS_ROOT}/openssl/openssl_lib_osx")
find_library(OPENSSL_CRYPTO_LIB NAMES libcrypto PATHS "${OPENSSL_LIB_DIR}" NO_DEFAULT_PATH)
find_library(OPENSSL_SSL_LIB    NAMES libssl    PATHS "${OPENSSL_LIB_DIR}" NO_DEFAULT_PATH)
if(NOT OPENSSL_CRYPTO_LIB OR NOT OPENSSL_SSL_LIB)
    message(FATAL_ERROR "OpenSSL libraries not found in ${OPENSSL_LIB_DIR}")
endif()
message(STATUS "OpenSSL crypto: ${OPENSSL_CRYPTO_LIB}")
message(STATUS "OpenSSL ssl:    ${OPENSSL_SSL_LIB}")

# ---- 链接 ----
target_link_libraries(xlog_macos
    comm
    mars-boost
    libzstd_static
    ${OPENSSL_CRYPTO_LIB}
    ${OPENSSL_SSL_LIB}
    "-framework Foundation"
    "-framework CoreFoundation"
    z        # 系统 zlib
)
```

- [ ] **Step 2: 验证文件存在且内容正确**

```bash
# 检查文件存在
ls mars/xlog/CMakeLists_macos.txt

# 验证 CMake 语法（需要 cmake 已安装）
cmake --version && echo "CMake OK"

# 查看文件内容快速检查（至少 110 行）
wc -l mars/xlog/CMakeLists_macos.txt
# 预期：约 110+ 行
```

- [ ] **Step 3: 提交**

```bash
git add mars/xlog/CMakeLists_macos.txt
git commit -m "build: 添加 xlog macOS dylib CMake 构建定义"
```

---

## Task 2: 创建 build_macos.py

**Files:**
- Create: `mars/xlog/build_macos.py`

参照 `mars/xlog/build_windows.py` 的整体结构，实现 macOS 专用的构建逻辑：分两架构 cmake 生成+构建，lipo 合并，输出 dylib。

- [ ] **Step 1: 创建 build_macos.py**

创建 `mars/xlog/build_macos.py`，内容如下：

```python
#!/usr/bin/env python3
"""
Build script for xlog macOS dylib.

Compiles the xlog module (and its dependencies: comm, boost, zstd) into a
macOS dynamic library. Outputs a Universal Binary libxlog.dylib (arm64 + x86_64).

Usage:
    python build_macos.py --config Release
    python build_macos.py --config Debug
    python build_macos.py --config Release --incremental
    python build_macos.py --config Release --output-dir /path/to/output
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
    lipo_libs,
    gen_mars_revision_file,
)

# ---- Constants ----

CMAKE_LISTS_FILE: str = os.path.join(SCRIPT_PATH, 'CMakeLists_macos.txt')
ARCHS = ['arm64', 'x86_64']
DEPLOYMENT_TARGET = '10.13'


# ---- Environment Check ----

def check_environment() -> bool:
    """Check that macOS build environment is ready."""
    if platform.system() != 'Darwin':
        print('Error: build_macos.py must be run on macOS.')
        return False

    if shutil.which('cmake') is None:
        print('Error: cmake not found. Install via: brew install cmake')
        return False

    ret = subprocess.call(
        ['xcode-select', '-p'],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL
    )
    if ret != 0:
        print('Error: Xcode Command Line Tools not installed.')
        print('  Install via: xcode-select --install')
        return False

    return True


# ---- CMake Steps ----

def cmake_generate(build_dir: str, arch: str, config: str) -> bool:
    """Run CMake configure/generate step for a single architecture."""
    # Verify CMakeLists_macos.txt exists
    if not os.path.isfile(CMAKE_LISTS_FILE):
        print(f'Error: CMakeLists_macos.txt not found at {CMAKE_LISTS_FILE}')
        return False

    # Copy CMakeLists_macos.txt into build dir as CMakeLists.txt
    wrapper_path: str = os.path.join(build_dir, 'CMakeLists.txt')
    shutil.copy2(CMAKE_LISTS_FILE, wrapper_path)

    cmake_cmd: str = (
        f'cmake "{build_dir}" '
        f'-G "Unix Makefiles" '
        f'-DCMAKE_BUILD_TYPE={config} '
        f'-DCMAKE_OSX_ARCHITECTURES={arch} '
        f'-DCMAKE_OSX_DEPLOYMENT_TARGET={DEPLOYMENT_TARGET} '
        f'-DXLOG_SOURCE_DIR="{SCRIPT_PATH.replace(os.sep, "/")}"'
    )
    print(f'[cmake generate/{arch}] {cmake_cmd}')
    ret: int = subprocess.call(cmake_cmd, cwd=build_dir, shell=True)
    return ret == 0


def cmake_build(build_dir: str, config: str) -> bool:
    """Run CMake build step."""
    cpu_count = os.cpu_count() or 4
    cmake_cmd: str = f'cmake --build "{build_dir}" --target xlog_macos --config {config} -- -j{cpu_count}'
    print(f'[cmake build] {cmake_cmd}')
    ret: int = subprocess.call(cmake_cmd, cwd=build_dir, shell=True)
    return ret == 0


# ---- Output Collection ----

def find_dylib(build_dir: str) -> Optional[str]:
    """Find the built libxlog.dylib in the build directory."""
    patterns = [
        os.path.join(build_dir, 'libxlog.dylib'),
        os.path.join(build_dir, '**', 'libxlog.dylib'),
    ]
    for pattern in patterns:
        matches = glob.glob(pattern, recursive=True)
        if matches:
            return matches[0]
    return None


def collect_outputs(build_dirs: dict, config: str, output_dir: str) -> bool:
    """
    Use lipo to merge per-architecture dylibs into a Universal Binary.
    build_dirs: {'arm64': '/path/arm64_build', 'x86_64': '/path/x86_64_build'}
    """
    config_output_dir: str = os.path.join(output_dir, config)
    os.makedirs(config_output_dir, exist_ok=True)

    arch_dylibs = []
    for arch in ARCHS:
        dylib_path = find_dylib(build_dirs[arch])
        if not dylib_path or not os.path.isfile(dylib_path):
            print(f'Error: libxlog.dylib not found for arch={arch} in {build_dirs[arch]}')
            return False
        arch_dylibs.append(dylib_path)
        print(f'  [{arch}] {dylib_path}')

    output_dylib: str = os.path.join(config_output_dir, 'libxlog.dylib')
    print(f'[lipo] Merging into Universal Binary: {output_dylib}')
    if not lipo_libs(arch_dylibs, output_dylib):
        return False

    print(f'  libxlog.dylib -> {config_output_dir}')
    return True


# ---- Main ----

def main() -> None:
    parser = argparse.ArgumentParser(
        description='Build xlog as a macOS dylib (Universal Binary: arm64 + x86_64)'
    )
    parser.add_argument(
        '--config',
        type=str,
        choices=['Release', 'Debug'],
        default='Release',
        help='Build configuration: Release or Debug (default: Release)'
    )
    parser.add_argument(
        '--incremental',
        action='store_true',
        default=False,
        help='Incremental build (skip cleaning the build directory)'
    )
    parser.add_argument(
        '--output-dir',
        type=str,
        default=None,
        help='Output directory (default: <repo_root>/samples/xlog_flutter/macos/libs)'
    )
    args = parser.parse_args()

    config: str = args.config
    incremental: bool = args.incremental

    # Default output: samples/xlog_flutter/macos/libs (relative to repo root)
    repo_root: str = os.path.normpath(os.path.join(MARS_PATH, '..'))
    default_output: str = os.path.join(repo_root, 'samples', 'xlog_flutter', 'macos', 'libs')
    output_dir: str = os.path.abspath(args.output_dir or default_output)

    # Per-architecture build temp directories
    build_base: str = os.path.join(SCRIPT_PATH, 'build')
    build_dirs = {
        arch: os.path.join(build_base, f'cmake_tmp_macos_{arch}')
        for arch in ARCHS
    }

    print('========== xlog macOS dylib Build ==========')
    print(f'  Config:      {config}')
    print(f'  Incremental: {incremental}')
    print(f'  Output:      {output_dir}')
    print(f'  Archs:       {", ".join(ARCHS)}')
    print()

    before_time: float = time.time()

    # Step 1: Check environment
    print('[1/5] Checking environment...')
    if not check_environment():
        sys.exit(1)

    # Step 2: Generate version info
    print('[2/5] Generating version info...')
    gen_mars_revision_file(os.path.join(MARS_PATH, 'comm'))

    # Step 3: Configure CMake for each architecture
    print('[3/5] Configuring CMake projects...')
    for arch in ARCHS:
        build_dir = build_dirs[arch]
        clean(build_dir, incremental)
        if not cmake_generate(build_dir, arch, config):
            print(f'!!!!!!!!!!!!!!!!!!CMake generate failed for arch={arch}!!!!!!!!!!!!!!!!!!!!')
            sys.exit(1)

    # Step 4: Build each architecture
    print(f'[4/5] Building xlog dylib ({config})...')
    for arch in ARCHS:
        build_dir = build_dirs[arch]
        print(f'  Building {arch}...')
        if not cmake_build(build_dir, config):
            print(f'!!!!!!!!!!!!!!!!!!Build failed for arch={arch}!!!!!!!!!!!!!!!!!!!!')
            sys.exit(1)

    # Step 5: Merge with lipo and collect outputs
    print('[5/5] Merging architectures and collecting outputs...')
    if not collect_outputs(build_dirs, config, output_dir):
        print('!!!!!!!!!!!!!!!!!!Output collection failed!!!!!!!!!!!!!!!!!!!!')
        sys.exit(1)

    after_time: float = time.time()

    print()
    print('==================== Build Complete ====================')
    print(f'  dylib:   {os.path.join(output_dir, config, "libxlog.dylib")}')
    print(f'  Time:    {int(after_time - before_time)}s')
    print()
    print('Verify with:')
    print(f'  lipo -info {os.path.join(output_dir, config, "libxlog.dylib")}')
    print(f'  otool -D   {os.path.join(output_dir, config, "libxlog.dylib")}')
    print('========================================================')


if __name__ == '__main__':
    main()
```

- [ ] **Step 2: 验证文件存在且语法正确**

```bash
python3 -c "import ast; ast.parse(open('mars/xlog/build_macos.py').read()); print('syntax OK')"
```

预期输出：`syntax OK`

- [ ] **Step 3: 提交**

```bash
git add mars/xlog/build_macos.py
git commit -m "build: 添加 xlog macOS dylib 构建脚本 build_macos.py"
```

---

## Task 3: 运行构建脚本，产出 libxlog.dylib

**Files:**
- Generate: `samples/xlog_flutter/macos/libs/Release/libxlog.dylib`

- [ ] **Step 1: 运行构建（Release）**

在 repo 根目录执行：

```bash
python3 mars/xlog/build_macos.py --config Release
```

预期：最终打印 `Build Complete`，无 `failed` 字样。

- [ ] **Step 2: 验证产物**

```bash
# 验证文件存在
ls -lh samples/xlog_flutter/macos/libs/Release/libxlog.dylib

# 验证是 Universal Binary
lipo -info samples/xlog_flutter/macos/libs/Release/libxlog.dylib
# 预期: Architectures in the fat file: ... are: x86_64 arm64

# 验证 install_name 为 @rpath
otool -D samples/xlog_flutter/macos/libs/Release/libxlog.dylib
# 预期包含: @rpath/libxlog.dylib

# 验证关键符号存在
nm samples/xlog_flutter/macos/libs/Release/libxlog.dylib | grep xlog_new_instance
# 预期: 找到 xlog_new_instance 符号（T 或 U 类型）
```

- [ ] **Step 3: 将产物提交 git**

```bash
git add samples/xlog_flutter/macos/libs/Release/libxlog.dylib
git commit -m "build(macos): 添加预编译 libxlog.dylib Universal Binary (arm64 + x86_64)"
```

---

## Task 4: 更新 macOS Podspec

**Files:**
- Modify: `samples/xlog_flutter/macos/xlog_flutter.podspec`

将 Podspec 从源码编译模式改为引用预编译 `libxlog.dylib`。

- [ ] **Step 1: 更新 xlog_flutter.podspec**

将 `samples/xlog_flutter/macos/xlog_flutter.podspec` 替换为：

```ruby
#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint xlog_flutter.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'xlog_flutter'
  s.version          = '0.0.1'
  s.summary          = 'Flutter FFI plugin for mars xlog.'
  s.description      = <<-DESC
Flutter FFI plugin for mars xlog multi-instance logging library.
Uses a prebuilt libxlog.dylib (Universal Binary: arm64 + x86_64).
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }

  s.source           = { :path => '.' }

  # Classes/ contains a forwarder xlog_flutter.c — required by Flutter FFI plugin structure.
  s.source_files = 'Classes/**/*'

  # Prebuilt libxlog.dylib (Universal Binary: arm64 + x86_64).
  # Build with: python3 mars/xlog/build_macos.py --config Release
  s.vendored_libraries = 'libs/Release/libxlog.dylib'
  s.preserve_paths = 'libs/**/*'

  s.dependency 'FlutterMacOS'

  s.platform = :osx, '10.13'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'OTHER_LDFLAGS' => '$(inherited) -rpath @loader_path/Frameworks'
  }
  s.swift_version = '5.0'
end
```

- [ ] **Step 2: 验证 Podspec 语法（可选，需要本机安装 CocoaPods）**

```bash
cd samples/xlog_flutter/macos && pod lib lint xlog_flutter.podspec --allow-warnings 2>&1 | tail -5
```

预期：`passed validation` 或无 ERROR 级别报错（WARNING 可忽略）。

若未安装 CocoaPods，跳过此步，在 Task 5 的 flutter run 中验证。

- [ ] **Step 3: 提交**

```bash
git add samples/xlog_flutter/macos/xlog_flutter.podspec
git commit -m "feat(macos): 更新 Podspec 使用预编译 libxlog.dylib"
```

---

## Task 5: 在 example 中运行并验证

**Files:**
- 无文件修改，仅运行验证

- [ ] **Step 1: 进入 example 目录，获取依赖**

```bash
cd samples/xlog_flutter/example
flutter pub get
```

预期：无 ERROR，依赖下载完成。

- [ ] **Step 2: 运行 flutter run**

```bash
flutter run -d macos
```

预期：
- 应用正常启动，无崩溃
- 无 `dylib not found` 或 `Library not loaded` 错误

- [ ] **Step 3: 确认日志功能正常**

在应用运行时，检查 example 应用是否正确调用了 xlog（查看控制台输出或应用的日志目录），确认以下无报错：
- xlog 初始化成功
- 日志写入无崩溃

- [ ] **Step 4: 如果 flutter run 失败，检查以下常见问题**

```bash
# 检查 dylib 的 install_name 是否正确
otool -D samples/xlog_flutter/macos/libs/Release/libxlog.dylib
# 应该是: @rpath/libxlog.dylib

# 检查 Pods 是否正确引用了 dylib
ls samples/xlog_flutter/example/macos/Pods/xlog_flutter/
```

---

## 可选 Task 6: 添加 Debug 构建产物

如果需要 Debug 版本（含调试符号），执行：

- [ ] **Step 1: 构建 Debug**

```bash
python3 mars/xlog/build_macos.py --config Debug
```

- [ ] **Step 2: 提交 Debug 产物**

```bash
git add samples/xlog_flutter/macos/libs/Debug/libxlog.dylib
git commit -m "build(macos): 添加 Debug 版预编译 libxlog.dylib"
```

---

## 关键参考文件

- 参照脚本：`mars/xlog/build_windows.py`（整体结构）
- 参照 CMake：`mars/xlog/CMakeLists_dll.txt`（依赖组织方式）
- 共享工具：`mars/mars_utils.py`（`lipo_libs`, `gen_mars_revision_file`, `clean`）
- OpenSSL：`mars/openssl/openssl_lib_osx/`（Universal Binary，已含 x86_64 + arm64）
- 现有 Podspec：`samples/xlog_flutter/ios/xlog_flutter.podspec`（参考 iOS 格式）
- 设计文档：`docs/superpowers/specs/2026-03-25-xlog-flutter-macos-build-design.md`
