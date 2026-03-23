#!/usr/bin/env python3
"""
Build script for xlog Windows DLL.

Compiles the xlog module (and its dependencies: comm, boost, zstd) into a
Windows dynamic link library. Outputs xlog.dll, xlog.lib, and xlog.pdb.

Usage:
    python build_windows.py --config Release
    python build_windows.py --config Debug
    python build_windows.py --config Release --incremental
    python build_windows.py --config Release --output-dir D:/output
"""

import os
import sys
import glob
import time
import shutil
import argparse
import subprocess
from typing import List, Dict, Optional

# ---- Path Setup ----

SCRIPT_PATH: str = os.path.dirname(os.path.realpath(__file__))
MARS_PATH: str = os.path.normpath(os.path.join(SCRIPT_PATH, '..'))

# Add mars/ directory to sys.path so we can import mars_utils
sys.path.insert(0, MARS_PATH)
from mars_utils import (
    clean_windows,
    check_vs_env,
    copy_file_mapping,
    gen_mars_revision_file,
    XLOG_COPY_HEADER_FILES,
    WIN_COPY_EXT_FILES,
)

# ---- Constants ----

CMAKE_LISTS_FILE: str = os.path.join(SCRIPT_PATH, 'CMakeLists_dll.txt')
CMAKE_GENERATOR: str = 'Visual Studio 17 2022'
CMAKE_ARCH: str = 'x64'


# ---- Header files to export ----

EXPORT_HEADER_FILES: Dict[str, str] = {}
EXPORT_HEADER_FILES.update(XLOG_COPY_HEADER_FILES)
EXPORT_HEADER_FILES.update(WIN_COPY_EXT_FILES)


def check_environment() -> bool:
    """Check that required MSVC environment variables are set."""
    if 'MSVC_TOOLS_PATH' not in os.environ:
        print('Error: MSVC_TOOLS_PATH environment variable is not set.')
        print('  Set it to your Visual Studio Common7/Tools path, e.g.:')
        print('  set MSVC_TOOLS_PATH=D:\\Program Files\\Microsoft Visual Studio\\2022\\Professional\\Common7\\Tools')
        return False

    vs_dev_cmd: str = os.path.join(os.environ['MSVC_TOOLS_PATH'], 'VsDevCmd.bat')
    if not os.path.isfile(vs_dev_cmd):
        print(f'Error: VsDevCmd.bat not found at: {vs_dev_cmd}')
        return False

    check_vs_env('"' + vs_dev_cmd + '"')
    return True


def cmake_generate(build_dir: str) -> bool:
    """Run CMake configure/generate step."""
    cmake_cmd: str = (
        f'cmake "{SCRIPT_PATH}" '
        f'-G "{CMAKE_GENERATOR}" '
        f'-A {CMAKE_ARCH} '
        f'-DCMAKE_INSTALL_PREFIX="{build_dir}"'
    )
    print(f'[cmake generate] {cmake_cmd}')

    # CMakeLists_dll.txt is in SCRIPT_PATH but named differently than CMakeLists.txt.
    # Copy it into the build dir as CMakeLists.txt so cmake can find it directly.
    wrapper_path: str = os.path.join(build_dir, 'CMakeLists.txt')
    shutil.copy2(CMAKE_LISTS_FILE, wrapper_path)

    cmake_cmd = (
        f'cmake "{build_dir}" '
        f'-G "{CMAKE_GENERATOR}" '
        f'-A {CMAKE_ARCH} '
        f'-DCMAKE_INSTALL_PREFIX="{build_dir}" '
        f'-DXLOG_SOURCE_DIR="{SCRIPT_PATH.replace(os.sep, "/")}"'
    )

    ret: int = subprocess.call(cmake_cmd, cwd=build_dir, shell=True)
    return ret == 0


def cmake_build(build_dir: str, config: str) -> bool:
    """Run CMake build step."""
    cmake_cmd: str = f'cmake --build "{build_dir}" --target xlog_dll --config {config}'
    print(f'[cmake build] {cmake_cmd}')
    ret: int = subprocess.call(cmake_cmd, cwd=build_dir, shell=True)
    return ret == 0


def collect_outputs(build_dir: str, config: str, output_dir: str) -> bool:
    """Copy built DLL, LIB, and PDB to the output directory."""
    config_output_dir: str = os.path.join(output_dir, config)
    os.makedirs(config_output_dir, exist_ok=True)

    collected: int = 0

    # DLL: typically in <build_dir>/<config>/xlog.dll
    dll_search_patterns: List[str] = [
        os.path.join(build_dir, config, 'xlog.dll'),
        os.path.join(build_dir, '**', config, 'xlog.dll'),
    ]

    dll_path: Optional[str] = None
    for pattern in dll_search_patterns:
        matches = glob.glob(pattern, recursive=True)
        if matches:
            dll_path = matches[0]
            break

    if dll_path and os.path.isfile(dll_path):
        shutil.copy2(dll_path, config_output_dir)
        print(f'  xlog.dll -> {config_output_dir}')
        collected += 1
    else:
        print(f'Warning: xlog.dll not found in build output')

    # Import LIB: typically in <build_dir>/<config>/xlog.lib
    lib_search_patterns: List[str] = [
        os.path.join(build_dir, config, 'xlog.lib'),
        os.path.join(build_dir, '**', config, 'xlog.lib'),
    ]

    lib_path: Optional[str] = None
    for pattern in lib_search_patterns:
        matches = glob.glob(pattern, recursive=True)
        if matches:
            lib_path = matches[0]
            break

    if lib_path and os.path.isfile(lib_path):
        shutil.copy2(lib_path, config_output_dir)
        print(f'  xlog.lib -> {config_output_dir}')
        collected += 1
    else:
        print(f'Warning: xlog.lib not found in build output')

    # PDB: typically in <build_dir>/<config>/xlog.pdb
    pdb_search_patterns: List[str] = [
        os.path.join(build_dir, config, 'xlog.pdb'),
        os.path.join(build_dir, '**', config, 'xlog.pdb'),
    ]

    pdb_path: Optional[str] = None
    for pattern in pdb_search_patterns:
        matches = glob.glob(pattern, recursive=True)
        if matches:
            pdb_path = matches[0]
            break

    if pdb_path and os.path.isfile(pdb_path):
        shutil.copy2(pdb_path, config_output_dir)
        print(f'  xlog.pdb -> {config_output_dir}')
        collected += 1
    else:
        print(f'Warning: xlog.pdb not found in build output')

    return collected >= 2  # At minimum DLL + LIB


def copy_headers(output_dir: str) -> None:
    """Copy public header files to the output include directory."""
    include_dir: str = os.path.join(output_dir, 'include')
    os.makedirs(include_dir, exist_ok=True)

    # XLOG_COPY_HEADER_FILES maps "mars/xlog/appender.h" -> "xlog" (subdirectory)
    # copy_file_mapping expects a base path to resolve src files from
    header_base: str = os.path.join(MARS_PATH, '..')  # parent of mars/

    copy_file_mapping(EXPORT_HEADER_FILES, header_base, include_dir)
    print(f'  Headers -> {include_dir}')


def main() -> None:
    parser = argparse.ArgumentParser(
        description='Build xlog as a Windows DLL (.dll + .lib + .pdb)'
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
        help='Output directory (default: <script_dir>/build/windows)'
    )
    args = parser.parse_args()

    config: str = args.config
    incremental: bool = args.incremental
    output_dir: str = args.output_dir or os.path.join(SCRIPT_PATH, 'build', 'windows')
    output_dir = os.path.abspath(output_dir)

    build_dir: str = os.path.join(SCRIPT_PATH, 'build', 'cmake_tmp')

    print(f'========== xlog DLL Build ==========')
    print(f'  Config:      {config}')
    print(f'  Incremental: {incremental}')
    print(f'  Output:      {output_dir}')
    print(f'  Build tmp:   {build_dir}')
    print()

    before_time: float = time.time()

    # Step 1: Check environment
    print('[1/5] Checking environment...')
    if not check_environment():
        sys.exit(1)

    # Step 2: Generate version info
    print('[2/5] Generating version info...')
    gen_mars_revision_file(os.path.join(MARS_PATH, 'comm'))

    # Step 3: Clean + CMake generate
    print('[3/5] Configuring CMake project...')
    clean_windows(build_dir, incremental)

    if not cmake_generate(build_dir):
        print('!!!!!!!!!!!!!!!!!!CMake generate failed!!!!!!!!!!!!!!!!!!!!')
        sys.exit(1)

    # Step 4: Build
    print(f'[4/5] Building xlog DLL ({config})...')
    if not cmake_build(build_dir, config):
        print('!!!!!!!!!!!!!!!!!!Build failed!!!!!!!!!!!!!!!!!!!!')
        sys.exit(1)

    # Step 5: Collect outputs
    print('[5/5] Collecting outputs...')
    if not collect_outputs(build_dir, config, output_dir):
        print('!!!!!!!!!!!!!!!!!!Output collection failed!!!!!!!!!!!!!!!!!!!!')
        sys.exit(1)

    copy_headers(output_dir)

    after_time: float = time.time()

    print()
    print('==================== Build Complete ====================')
    print(f'  DLL:     {os.path.join(output_dir, config, "xlog.dll")}')
    print(f'  LIB:     {os.path.join(output_dir, config, "xlog.lib")}')
    print(f'  PDB:     {os.path.join(output_dir, config, "xlog.pdb")}')
    print(f'  Headers: {os.path.join(output_dir, "include")}')
    print(f'  Time:    {int(after_time - before_time)}s')
    print('========================================================')


if __name__ == '__main__':
    main()
