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
