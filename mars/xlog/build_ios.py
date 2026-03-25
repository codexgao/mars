#!/usr/bin/env python3
"""
Build script for xlog iOS Static Framework.

Compiles the xlog module (and its dependencies: comm, boost, zstd, OpenSSL)
into a Universal Static Framework (xlog.framework) containing:
  - Device slice:    arm64   (iphoneos)
  - Simulator slice: x86_64  (iphonesimulator)

Note: OpenSSL arm64-simulator slice is not available in the prebuilt
openssl_lib_iOS archive, so arm64 simulator is excluded. The framework
covers real device (arm64) and Intel simulator (x86_64) targets.

Outputs xlog.framework to the configured output directory.

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

# Two compilation targets: (key, sysroot, arch)
# arm64-simulator is excluded because the prebuilt OpenSSL does not include
# an arm64-simulator slice, and we need OpenSSL in every slice.
IOS_TARGETS = [
    ('device',  'iphoneos',        'arm64'),
    ('sim_x86', 'iphonesimulator', 'x86_64'),
]

# Headers to include in xlog.framework/Headers/
# Only the C API header that Flutter FFI consumers need.
FRAMEWORK_HEADERS = [
    os.path.join(SCRIPT_PATH, 'capi', 'xlog_capi.h'),
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


def merge_all_deps(build_dir: str, arch: str, out_a: str) -> bool:
    """
    Merge libxlog.a together with all its static dependencies into a single
    self-contained archive.

    Dependencies built by CMake:
      comm/libcomm.a
      boost/libmars-boost.a
      zstd/libzstd.a

    OpenSSL (thinned to target arch from the prebuilt fat binary):
      openssl_lib_iOS/libcrypto.a  → thinned to arch
      openssl_lib_iOS/libssl.a     → thinned to arch

    The resulting archive is fully self-contained; consumers only need to
    link the system frameworks (Foundation, CoreFoundation, z).
    """
    xlog_a  = os.path.join(build_dir, 'libxlog.a')
    comm_a  = os.path.join(build_dir, 'comm', 'libcomm.a')
    boost_a = os.path.join(build_dir, 'boost', 'libmars-boost.a')
    zstd_a  = os.path.join(build_dir, 'zstd', 'libzstd.a')

    for path in (xlog_a, comm_a, boost_a, zstd_a):
        if not os.path.isfile(path):
            print(f'Error: dependency not found: {path}')
            return False

    # Thin OpenSSL fat binaries to the target arch.
    # The prebuilt openssl_lib_iOS contains arm64 (device) + x86_64 (simulator).
    openssl_lib_dir = os.path.join(MARS_PATH, 'openssl', 'openssl_lib_iOS')
    openssl_crypto_fat = os.path.join(openssl_lib_dir, 'libcrypto.a')
    openssl_ssl_fat    = os.path.join(openssl_lib_dir, 'libssl.a')

    thin_dir = os.path.join(build_dir, 'openssl_thin')
    os.makedirs(thin_dir, exist_ok=True)
    crypto_thin = os.path.join(thin_dir, 'libcrypto.a')
    ssl_thin    = os.path.join(thin_dir, 'libssl.a')

    for fat, thin in ((openssl_crypto_fat, crypto_thin), (openssl_ssl_fat, ssl_thin)):
        if not os.path.isfile(fat):
            print(f'Error: OpenSSL fat lib not found: {fat}')
            return False
        ret = subprocess.call(
            ['lipo', fat, '-thin', arch, '-output', thin],
            stdout=subprocess.DEVNULL,
        )
        if ret != 0:
            print(f'Error: lipo -thin {arch} failed for {fat}')
            return False

    print(f'[libtool] Merging all deps into {out_a} (arch={arch})')
    return libtool_libs([xlog_a, comm_a, boost_a, zstd_a, crypto_thin, ssl_thin], out_a)


def create_fat_lib(device_a: str, sim_a: str, out_a: str) -> bool:
    """
    Use lipo -create to combine per-architecture static archives into a
    Universal (fat) binary.

    Note: lipo works here because each input .a is already a single-arch
    archive (not a fat binary). lipo -create produces a fat archive.
    """
    os.makedirs(os.path.dirname(out_a), exist_ok=True)
    print(f'[lipo] Creating fat lib:')
    print(f'  device (arm64): {device_a}')
    print(f'  sim (x86_64):   {sim_a}')
    print(f'  output:         {out_a}')
    ret = subprocess.call(['lipo', '-create', device_a, sim_a, '-output', out_a])
    if ret != 0:
        print('Error: lipo -create failed.')
        return False
    return True


def create_framework(fat_a: str, framework_dir: str) -> bool:
    """
    Assemble a Static Framework from a fat static archive and the C API headers.

    xlog.framework/
      xlog          ← fat static library (the binary)
      Headers/
        xlog_capi.h ← public C API header
      Info.plist    ← minimal framework plist
    """
    # Clean and create framework directory
    if os.path.exists(framework_dir):
        shutil.rmtree(framework_dir)
    os.makedirs(framework_dir, exist_ok=True)

    # 1. Copy binary (no extension, just the framework name)
    framework_name = os.path.splitext(os.path.basename(framework_dir))[0]
    binary_dst = os.path.join(framework_dir, framework_name)
    shutil.copy2(fat_a, binary_dst)
    print(f'  binary  -> {binary_dst}')

    # 2. Copy headers
    headers_dir = os.path.join(framework_dir, 'Headers')
    os.makedirs(headers_dir, exist_ok=True)
    for h in FRAMEWORK_HEADERS:
        if not os.path.isfile(h):
            print(f'Warning: header not found: {h}')
            continue
        dst = os.path.join(headers_dir, os.path.basename(h))
        shutil.copy2(h, dst)
        print(f'  header  -> {dst}')

    # 3. Write minimal Info.plist
    info_plist = os.path.join(framework_dir, 'Info.plist')
    plist_content = f'''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
    "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>{framework_name}</string>
    <key>CFBundleIdentifier</key>
    <string>com.tencent.mars.{framework_name}</string>
    <key>CFBundleName</key>
    <string>{framework_name}</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>MinimumOSVersion</key>
    <string>{DEPLOYMENT_TARGET}</string>
</dict>
</plist>
'''
    with open(info_plist, 'w') as f:
        f.write(plist_content)
    print(f'  plist   -> {info_plist}')

    return True


# ---- Main ----

def main() -> None:
    parser = argparse.ArgumentParser(
        description=(
            'Build xlog as an iOS Static Framework '
            '(device: arm64, simulator: x86_64)'
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

    # Intermediate fat lib and final framework
    fat_dir: str = os.path.join(build_base, 'cmake_tmp_ios_fat')
    fat_a:   str = os.path.join(fat_dir, 'xlog')

    config_output_dir: str = os.path.join(output_dir, config)
    output_framework: str = os.path.join(config_output_dir, 'xlog.framework')

    print('========== xlog iOS Static Framework Build ==========')
    print(f'  Config:      {config}')
    print(f'  Incremental: {incremental}')
    print(f'  Output:      {output_dir}')
    print(f'  Targets:     {", ".join(k for k, _, _ in IOS_TARGETS)}')
    print()

    before_time: float = time.time()

    # Step 1: Check environment
    print('[1/5] Checking environment...')
    if not check_environment():
        sys.exit(1)

    # Step 2: Generate version info
    print('[2/5] Generating version info...')
    gen_mars_revision_file(os.path.join(MARS_PATH, 'comm'))

    # Step 3: Configure + build each target
    print(f'[3/5] Building xlog static libs ({config})...')
    built_libs: dict = {}
    for key, sysroot, arch in IOS_TARGETS:
        build_dir = build_dirs[key]
        clean(build_dir, incremental)
        if not cmake_generate(build_dir, sysroot, arch, config):
            print(f'!!!!!!!!!!!!!!!!!!CMake generate failed for {key}!!!!!!!!!!!!!!!!!!!!')
            sys.exit(1)
        if not cmake_build(build_dir, config, key):
            print(f'!!!!!!!!!!!!!!!!!!Build failed for {key}!!!!!!!!!!!!!!!!!!!!')
            sys.exit(1)

        lib_path = find_static_lib(build_dir)
        if not lib_path or not os.path.isfile(lib_path):
            print(f'Error: libxlog.a not found after build for target={key}')
            sys.exit(1)

        # Merge xlog + comm + boost + zstd + OpenSSL (thinned) into one archive.
        # Output named 'xlog' (no lib prefix) to match the framework binary name.
        merged_dir = os.path.join(build_dir, 'merged')
        os.makedirs(merged_dir, exist_ok=True)
        merged_a = os.path.join(merged_dir, 'xlog')
        if not merge_all_deps(build_dir, arch, merged_a):
            print(f'!!!!!!!!!!!!!!!!!!Dependency merge failed for {key}!!!!!!!!!!!!!!!!!!!!')
            sys.exit(1)
        built_libs[key] = merged_a
        print(f'  [{key}] {merged_a}')

    # Step 4: Create fat (Universal) static lib via lipo
    print('[4/5] Creating Universal fat library...')
    os.makedirs(fat_dir, exist_ok=True)
    if not create_fat_lib(built_libs['device'], built_libs['sim_x86'], fat_a):
        print('!!!!!!!!!!!!!!!!!!Fat lib creation failed!!!!!!!!!!!!!!!!!!!!')
        sys.exit(1)

    # Step 5: Assemble framework
    print('[5/5] Assembling xlog.framework...')
    os.makedirs(config_output_dir, exist_ok=True)
    if not create_framework(fat_a, output_framework):
        print('!!!!!!!!!!!!!!!!!!Framework assembly failed!!!!!!!!!!!!!!!!!!!!')
        sys.exit(1)

    after_time: float = time.time()

    print()
    print('==================== Build Complete ====================')
    print(f'  Framework: {output_framework}')
    print(f'  Time:      {int(after_time - before_time)}s')
    print()
    print('Verify with:')
    print(f'  ls {output_framework}')
    print(f'  lipo -info {output_framework}/xlog')
    print('========================================================')


if __name__ == '__main__':
    main()
