#!/usr/bin/env python3
"""
Build script for xlog Android SO.

Compiles the xlog module (and its dependencies: comm, boost, zstd) into an
Android shared library (.so). Outputs libxlog.so for multiple architectures.

Usage:
    python build_android.py --config Release
    python build_android.py --config Debug
    python build_android.py --config Release --incremental
    python build_android.py --config Release --output-dir D:/output
"""

import os
import sys
import glob
import time
import shutil
import argparse
import subprocess
import platform
from typing import List, Optional

# ---- Path Setup ----

SCRIPT_PATH: str = os.path.dirname(os.path.realpath(__file__))
MARS_PATH: str = os.path.normpath(os.path.join(SCRIPT_PATH, '..'))

# Add mars/ directory to sys.path so we can import mars_utils
sys.path.insert(0, MARS_PATH)
from mars_utils import (
    clean,
    copy_file_mapping,
    gen_mars_revision_file,
    XLOG_COPY_HEADER_FILES,
)

# ---- Constants ----

CMAKE_LISTS_FILE: str = os.path.join(SCRIPT_PATH, 'CMakeLists_android.txt')
SUPPORTED_ARCHS: List[str] = ['armeabi-v7a', 'arm64-v8a', 'x86', 'x86_64']
DEFAULT_ARCHS: List[str] = ['armeabi-v7a', 'arm64-v8a']


def system_is_windows() -> bool:
    return platform.system() == 'Windows'


def system_architecture_is64() -> bool:
    return platform.machine().endswith('64')


def get_ndk_host_tag() -> str:
    """Get NDK host tag for the current platform."""
    system = platform.system().lower()
    if system == 'windows':
        if system_architecture_is64():
            return 'windows-x86_64'
        return 'windows'
    elif system == 'darwin':
        return 'darwin-x86_64'
    elif system == 'linux':
        if system_architecture_is64():
            return 'linux-x86_64'
        return 'linux'
    return system


def check_environment() -> bool:
    """Check that required NDK environment variables are set."""
    if 'NDK_ROOT' not in os.environ:
        print('Error: NDK_ROOT environment variable is not set.')
        print('  Set it to your Android NDK path, e.g.:')
        print('  set NDK_ROOT=D:\\Android\\Sdk\\ndk\\25.2.9519653')
        return False

    ndk_root: str = os.environ['NDK_ROOT']
    if not os.path.isdir(ndk_root):
        print(f'Error: NDK_ROOT directory does not exist: {ndk_root}')
        return False

    toolchain_file = os.path.join(ndk_root, 'build', 'cmake', 'android.toolchain.cmake')
    if not os.path.isfile(toolchain_file):
        print(f'Error: Android toolchain file not found: {toolchain_file}')
        return False

    return True


def get_executable_name(name: str) -> str:
    """Get executable name with .exe extension on Windows."""
    return f'{name}.exe' if system_is_windows() else name


def get_android_strip_cmd(ndk_root: str, arch: str) -> Optional[str]:
    """Get the strip command for the given architecture."""
    host_tag = get_ndk_host_tag()
    exe_ext = '.exe' if system_is_windows() else ''

    # NDK r23+ uses unified toolchain
    strip_path = os.path.join(
        ndk_root, 'toolchains', 'llvm', 'prebuilt', host_tag, 'bin', f'llvm-strip{exe_ext}'
    )
    if os.path.isfile(strip_path):
        return strip_path

    # Fallback to older NDK toolchain structure (r22 and below)
    old_strip_map = {
        'armeabi': f'{ndk_root}/toolchains/arm-linux-androideabi-4.9/prebuilt/{host_tag}/bin/arm-linux-androideabi-strip{exe_ext}',
        'armeabi-v7a': f'{ndk_root}/toolchains/arm-linux-androideabi-4.9/prebuilt/{host_tag}/bin/arm-linux-androideabi-strip{exe_ext}',
        'x86': f'{ndk_root}/toolchains/x86-4.9/prebuilt/{host_tag}/bin/i686-linux-android-strip{exe_ext}',
        'arm64-v8a': f'{ndk_root}/toolchains/aarch64-linux-android-4.9/prebuilt/{host_tag}/bin/aarch64-linux-android-strip{exe_ext}',
        'x86_64': f'{ndk_root}/toolchains/x86_64-4.9/prebuilt/{host_tag}/bin/x86_64-linux-android-strip{exe_ext}',
    }

    if arch in old_strip_map:
        strip_path = old_strip_map[arch]
        if os.path.isfile(strip_path):
            return strip_path

    return None


def get_cxx_shared_lib(ndk_root: str, arch: str) -> Optional[str]:
    """Get the path to libc++_shared.so for the given architecture."""
    host_tag = get_ndk_host_tag()

    # NDK r23+ path
    cxx_shared = os.path.join(
        ndk_root, 'toolchains', 'llvm', 'prebuilt', host_tag,
        'sysroot', 'usr', 'lib', arch, 'libc++_shared.so'
    )
    if os.path.isfile(cxx_shared):
        return cxx_shared

    # Older NDK path
    cxx_shared_old = os.path.join(
        ndk_root, 'sources', 'cxx-stl', 'llvm-libc++', 'libs', arch, 'libc++_shared.so'
    )
    if os.path.isfile(cxx_shared_old):
        return cxx_shared_old

    return None


def cmake_generate(build_dir: str, ndk_root: str, arch: str, config: str) -> bool:
    """Run CMake configure/generate step for Android."""
    toolchain_file = os.path.join(ndk_root, 'build', 'cmake', 'android.toolchain.cmake')

    # Copy CMakeLists_android.txt to build dir as CMakeLists.txt
    wrapper_path: str = os.path.join(build_dir, 'CMakeLists.txt')
    shutil.copy2(CMAKE_LISTS_FILE, wrapper_path)

    generator = '-G "Unix Makefiles"' if system_is_windows() else ''

    cmake_cmd: str = (
        f'cmake "{build_dir}" '
        f'{generator} '
        f'-DANDROID_ABI="{arch}" '
        f'-DCMAKE_BUILD_TYPE={config} '
        f'-DCMAKE_TOOLCHAIN_FILE="{toolchain_file}" '
        f'-DANDROID_TOOLCHAIN=clang '
        f'-DANDROID_NDK="{ndk_root}" '
        f'-DANDROID_PLATFORM=android-21 '
        f'-DANDROID_STL=c++_shared '
        f'-DXLOG_SOURCE_DIR="{SCRIPT_PATH.replace(os.sep, "/")}"'
    )

    print(f'[cmake generate] {cmake_cmd}')

    ret: int = subprocess.call(cmake_cmd, cwd=build_dir, shell=True)
    return ret == 0


def cmake_build(build_dir: str) -> bool:
    """Run CMake build step."""
    cmake_cmd: str = f'cmake --build "{build_dir}" -- -j8'
    print(f'[cmake build] {cmake_cmd}')
    ret: int = subprocess.call(cmake_cmd, cwd=build_dir, shell=True)
    return ret == 0


def get_android_objcopy_cmd(ndk_root: str, arch: str) -> Optional[str]:
    """Get the objcopy command for the given architecture."""
    host_tag = get_ndk_host_tag()
    exe_ext = '.exe' if system_is_windows() else ''

    # NDK r23+ uses unified toolchain
    objcopy_path = os.path.join(
        ndk_root, 'toolchains', 'llvm', 'prebuilt', host_tag, 'bin', f'llvm-objcopy{exe_ext}'
    )
    if os.path.isfile(objcopy_path):
        return objcopy_path

    # Fallback to older NDK toolchain structure (r22 and below)
    old_objcopy_map = {
        'armeabi': f'{ndk_root}/toolchains/arm-linux-androideabi-4.9/prebuilt/{host_tag}/bin/arm-linux-androideabi-objcopy{exe_ext}',
        'armeabi-v7a': f'{ndk_root}/toolchains/arm-linux-androideabi-4.9/prebuilt/{host_tag}/bin/arm-linux-androideabi-objcopy{exe_ext}',
        'x86': f'{ndk_root}/toolchains/x86-4.9/prebuilt/{host_tag}/bin/i686-linux-android-objcopy{exe_ext}',
        'arm64-v8a': f'{ndk_root}/toolchains/aarch64-linux-android-4.9/prebuilt/{host_tag}/bin/aarch64-linux-android-objcopy{exe_ext}',
        'x86_64': f'{ndk_root}/toolchains/x86_64-4.9/prebuilt/{host_tag}/bin/x86_64-linux-android-objcopy{exe_ext}',
    }

    if arch in old_objcopy_map:
        objcopy_path = old_objcopy_map[arch]
        if os.path.isfile(objcopy_path):
            return objcopy_path

    return None


def collect_outputs(build_dir: str, arch: str, output_dir: str, ndk_root: str, config: str) -> bool:
    """Copy built SO to the output directory and strip debug symbols."""
    arch_output_dir: str = os.path.join(output_dir, arch)
    os.makedirs(arch_output_dir, exist_ok=True)

    # Find libxlog.so
    so_patterns: List[str] = [
        os.path.join(build_dir, 'libxlog.so'),
        os.path.join(build_dir, '**', 'libxlog.so'),
    ]

    so_path: Optional[str] = None
    for pattern in so_patterns:
        matches = glob.glob(pattern, recursive=True)
        if matches:
            so_path = matches[0]
            break

    if not so_path or not os.path.isfile(so_path):
        print(f'Error: libxlog.so not found in build output')
        return False

    # Copy to final output
    final_so_path = os.path.join(arch_output_dir, 'libxlog.so')
    shutil.copy2(so_path, final_so_path)

    # Release mode: separate debug symbols to symbols directory, then strip SO
    # Debug mode: keep symbols in the SO, no symbols directory needed
    if config == 'Release':
        # Create symbol directory only for Release mode
        symbol_dir: str = os.path.join(output_dir, 'symbols', arch)
        os.makedirs(symbol_dir, exist_ok=True)

        objcopy_cmd = get_android_objcopy_cmd(ndk_root, arch)
        if objcopy_cmd:
            # Extract debug symbols to a separate file in symbols directory
            debug_file = os.path.join(symbol_dir, 'libxlog.so.debug')
            extract_cmd = f'"{objcopy_cmd}" --only-keep-debug "{final_so_path}" "{debug_file}"'
            subprocess.call(extract_cmd, shell=True)
            print(f'  libxlog.so.debug (debug symbols) -> {symbol_dir}')

            # Strip the SO in final output
            strip_cmd = get_android_strip_cmd(ndk_root, arch)
            if strip_cmd:
                subprocess.call(f'"{strip_cmd}" "{final_so_path}"', shell=True)
                print(f'  libxlog.so (stripped) -> {arch_output_dir}')

            # Add .gnu_debuglink to link SO with debug symbols
            link_cmd = f'"{objcopy_cmd}" --add-gnu-debuglink="{debug_file}" "{final_so_path}"'
            subprocess.call(link_cmd, shell=True)
        else:
            # Fallback: just strip without separate debug file
            strip_cmd = get_android_strip_cmd(ndk_root, arch)
            if strip_cmd:
                subprocess.call(f'"{strip_cmd}" "{final_so_path}"', shell=True)
                print(f'  libxlog.so (stripped) -> {arch_output_dir}')
            else:
                print(f'  Warning: strip command not found, using unstripped library')
    else:
        # Debug mode: SO already contains symbols
        print(f'  libxlog.so (with symbols, Debug mode) -> {arch_output_dir}')

    # Copy libc++_shared.so if found
    cxx_shared = get_cxx_shared_lib(ndk_root, arch)
    if cxx_shared:
        shutil.copy2(cxx_shared, arch_output_dir)
        print(f'  libc++_shared.so -> {arch_output_dir}')
    else:
        print(f'  Warning: libc++_shared.so not found')

    return True


def copy_headers(output_dir: str) -> None:
    """Copy public header files to the output include directory."""
    include_dir: str = os.path.join(output_dir, 'include')
    os.makedirs(include_dir, exist_ok=True)

    header_base: str = os.path.join(MARS_PATH, '..')
    copy_file_mapping(XLOG_COPY_HEADER_FILES, header_base, include_dir)
    print(f'  Headers -> {include_dir}')


def main() -> None:
    parser = argparse.ArgumentParser(
        description='Build xlog as an Android SO (.so) for multiple architectures'
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
        help='Output directory (default: <script_dir>/build/android)'
    )
    parser.add_argument(
        '--arch',
        type=str,
        nargs='+',
        choices=SUPPORTED_ARCHS,
        default=DEFAULT_ARCHS,
        help=f'Android architectures to build (default: {" ".join(DEFAULT_ARCHS)})'
    )
    parser.add_argument(
        '--copy-headers',
        action='store_true',
        default=False,
        help='Copy public headers to <output_dir>/include (default: disabled)'
    )
    args = parser.parse_args()

    config: str = args.config
    incremental: bool = args.incremental
    archs: List[str] = args.arch
    copy_headers_enabled: bool = args.copy_headers
    output_dir: str = args.output_dir or os.path.join(SCRIPT_PATH, 'build', 'android')
    output_dir = os.path.abspath(output_dir)

    ndk_root: str = os.environ['NDK_ROOT']

    print(f'========== xlog Android SO Build ==========')
    print(f'  Config:      {config}')
    print(f'  Incremental: {incremental}')
    print(f'  Output:      {output_dir}')
    print(f'  Archs:       {", ".join(archs)}')
    print(f'  NDK:         {ndk_root}')
    print()

    before_time: float = time.time()

    # Step 1: Check environment
    print('[1/5] Checking environment...')
    if not check_environment():
        sys.exit(1)

    # Step 2: Generate version info
    print('[2/5] Generating version info...')
    gen_mars_revision_file(os.path.join(MARS_PATH, 'comm'))

    # Step 3: Clean output directory (only if not incremental)
    print('[3/5] Preparing build directories...')
    if not incremental:
        if os.path.exists(output_dir):
            shutil.rmtree(output_dir)

    # Step 4: Build each architecture
    print('[4/5] Building for architectures...')
    for arch in archs:
        print(f'\n  --- Building {arch} ---')

        build_dir: str = os.path.join(SCRIPT_PATH, 'build', f'cmake_tmp_{arch}')
        clean(build_dir, incremental)

        if not cmake_generate(build_dir, ndk_root, arch, config):
            print(f'!!!!!!!!!!!!!!!!!!CMake generate failed for {arch}!!!!!!!!!!!!!!!!!!!!')
            sys.exit(1)

        if not cmake_build(build_dir):
            print(f'!!!!!!!!!!!!!!!!!!Build failed for {arch}!!!!!!!!!!!!!!!!!!!!')
            sys.exit(1)

        if not collect_outputs(build_dir, arch, output_dir, ndk_root, config):
            print(f'!!!!!!!!!!!!!!!!!!Output collection failed for {arch}!!!!!!!!!!!!!!!!!!!!')
            sys.exit(1)

    # Step 5: Collect optional outputs
    print('\n[5/5] Collecting outputs...')
    if copy_headers_enabled:
        copy_headers(output_dir)
    else:
        print('  Headers -> skipped (use --copy-headers to enable)')

    after_time: float = time.time()

    print()
    print('==================== Build Complete ====================')
    for arch in archs:
        print(f'  {arch}:')
        print(f'    SO:     {os.path.join(output_dir, arch, "libxlog.so")}')
    if copy_headers_enabled:
        print(f'  Headers: {os.path.join(output_dir, "include")}')
    else:
        print('  Headers: skipped')
    print(f'  Symbols: {os.path.join(output_dir, "symbols")}')
    print(f'  Time:    {int(after_time - before_time)}s')
    print('========================================================')


if __name__ == '__main__':
    main()
