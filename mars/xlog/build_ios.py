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
    ('device',    'iphoneos',       'arm64'),
    ('sim_x86',   'iphonesimulator', 'x86_64'),
    ('sim_arm64', 'iphonesimulator', 'arm64'),
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

    Dependencies built by CMake (found in build_dir subdirs):
      comm/libcomm.a
      boost/libmars-boost.a
      zstd/libzstd.a

    OpenSSL (prebuilt fat library, thinned to target arch):
      openssl_lib_iOS/libcrypto.a
      openssl_lib_iOS/libssl.a

    The resulting archive is fully self-contained; consumers only need to
    link libxlog.a and the system frameworks (Foundation, CoreFoundation, z).
    """
    xlog_a    = os.path.join(build_dir, 'libxlog.a')
    comm_a    = os.path.join(build_dir, 'comm', 'libcomm.a')
    boost_a   = os.path.join(build_dir, 'boost', 'libmars-boost.a')
    zstd_a    = os.path.join(build_dir, 'zstd', 'libzstd.a')

    for path in (xlog_a, comm_a, boost_a, zstd_a):
        if not os.path.isfile(path):
            print(f'Error: dependency not found: {path}')
            return False

    # NOTE: OpenSSL is NOT merged here. The prebuilt openssl_lib_iOS only
    # contains a fat binary with iphoneos arm64 + x86_64 simulator, but lacks
    # an arm64-simulator slice. Merging it would cause xcodebuild
    # -create-xcframework to fail with "binaries with multiple platforms".
    # OpenSSL symbols are provided at link time via the podspec's
    # vendored_frameworks referencing OpenSSL.xcframework.
    print(f'[libtool] Merging all deps into {out_a} (arch={arch})')
    return libtool_libs([xlog_a, comm_a, boost_a, zstd_a], out_a)


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

    # Step 4: Build each target and merge all deps into self-contained archive
    print(f'[4/6] Building xlog static libs ({config})...')
    built_libs: dict = {}
    for key, _, arch in IOS_TARGETS:
        build_dir = build_dirs[key]
        print(f'  Building {key}...')
        if not cmake_build(build_dir, config, key):
            print(f'!!!!!!!!!!!!!!!!!!Build failed for {key}!!!!!!!!!!!!!!!!!!!!')
            sys.exit(1)

        lib_path = find_static_lib(build_dir)
        if not lib_path or not os.path.isfile(lib_path):
            print(f'Error: libxlog.a not found after build for target={key}')
            sys.exit(1)

        # Merge xlog + all dependency libs into one self-contained archive.
        # Without this, the app linker cannot resolve symbols from comm/boost/zstd/OpenSSL.
        # NOTE: The output must be named 'libxlog.a' in all slices so that CocoaPods
        # validation passes (it requires all platform slices to share the same binary name).
        merged_dir = os.path.join(build_dir, 'merged')
        os.makedirs(merged_dir, exist_ok=True)
        full_a = os.path.join(merged_dir, 'libxlog.a')
        if not merge_all_deps(build_dir, arch, full_a):
            print(f'!!!!!!!!!!!!!!!!!!Dependency merge failed for {key}!!!!!!!!!!!!!!!!!!!!')
            sys.exit(1)
        built_libs[key] = full_a
        print(f'  [{key}] {full_a}')

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

    # Copy OpenSSL.xcframework to output so podspec can reference it.
    # The prebuilt openssl_lib_iOS/libcrypto.a lacks an arm64-simulator slice,
    # so we cannot merge OpenSSL into libxlog.xcframework. Instead we ship
    # OpenSSL.xcframework as a sibling vendored_frameworks entry in the podspec.
    openssl_src = os.path.join(MARS_PATH, 'openssl', 'openssl_lib_iOS', 'OpenSSL.xcframework')
    openssl_dst = os.path.join(output_dir, 'openssl', 'OpenSSL.xcframework')
    if os.path.isdir(openssl_src):
        if os.path.exists(openssl_dst):
            shutil.rmtree(openssl_dst)
        shutil.copytree(openssl_src, openssl_dst)
        print(f'  OpenSSL.xcframework -> {openssl_dst}')
    else:
        print(f'Warning: OpenSSL.xcframework not found at {openssl_src}')

    after_time: float = time.time()

    print()
    print('==================== Build Complete ====================')
    print(f'  XCFramework: {output_xcframework}')
    print(f'  Time:        {int(after_time - before_time)}s')
    print()
    print('Verify with:')
    print(f'  ls {output_xcframework}')
    print('========================================================')


if __name__ == '__main__':
    main()
