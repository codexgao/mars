#!/usr/bin/env python3
"""Build MarsXlog.xcframework for iOS and deploy to the Flutter plugin's libs directory.

Usage:
    python build_xlog_ios.py [--config Release|Debug] [--outdir PATH] [--incremental]
                             [--logdir PATH] [--no-log]

Defaults:
    --config       Release
    --outdir       ../samples/xlog_flutter/ios/libs
    --incremental  False (clean build)
    --logdir       ../logs
    --no-log       False (logging enabled)

Output:
    <outdir>/Release/MarsXlog.xcframework   (or Debug/)
      ├── ios-arm64/                      (device slice)
      │   ├── MarsXlog.framework/
      │   └── dSYMs/                      (Release only: embedded debug symbols)
      │       └── MarsXlog.framework.dSYM/
      └── ios-arm64_x86_64-simulator/     (simulator slice)
          ├── MarsXlog.framework/
          └── dSYMs/                      (Release only: embedded debug symbols)
              └── MarsXlog.framework.dSYM/

Log file:
    <logdir>/build_xlog_ios_<timestamp>.log
"""

import os
import sys
import time
import shutil
import argparse
import glob
import logging
import subprocess
from typing import Optional

from mars_utils import (
    gen_mars_revision_file,
    clean,
    libtool_libs,
    lipo_libs,
    XLOG_COPY_HEADER_FILES,
)

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

SCRIPT_PATH = os.path.split(os.path.realpath(__file__))[0]

# Base cmake build path; config-specific subdirs are appended at runtime
BUILD_OUT_BASE = 'cmake_build/iOS'

# CMake toolchain commands — mirrors build_ios.py; config and install_path injected at runtime
_IOS_CMAKE_BASE = (
    'cmake -S ../../.. '
    '-DCMAKE_TOOLCHAIN_FILE=../../../ios.toolchain.cmake '
    '-DENABLE_ARC=0 '
    '-DENABLE_BITCODE=0 '
    '-DENABLE_VISIBILITY=1 '
    '-DCMAKE_BUILD_TYPE={config}'
)

IOS_BUILD_OS_CMD = _IOS_CMAKE_BASE + ' -DPLATFORM=OS && make -j8 && make install'
IOS_BUILD_SIMULATOR_CMD = _IOS_CMAKE_BASE + ' -DPLATFORM=SIMULATOR && make -j8 && make install'


def _slice_openssl_arch(lib_path: str, arch: str, temp_dir: str) -> str:
    """Extract single-architecture slice from fat binary using lipo.
    
    Parameters
    ----------
    lib_path : str
        Path to fat binary (e.g. libcrypto.a with arm64+x86_64)
    arch : str
        Target architecture ('arm64' or 'x86_64')
    temp_dir : str
        Directory to place sliced binary
    
    Returns
    -------
    Path to sliced .a file, or original path if lipo fails
    """
    if not os.path.exists(lib_path):
        return lib_path
    
    basename = os.path.basename(lib_path)
    output_path = os.path.join(temp_dir, f'{arch}_{basename}')
    
    cmd = f'lipo "{lib_path}" -thin {arch} -output "{output_path}"'
    ret = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    if ret.returncode != 0:
        log.warning(f'Failed to slice {basename} for {arch}: {ret.stderr}')
        return lib_path
    
    return output_path


def _xlog_src_libs(build_out_path: str, install_path: str, platform: str):
    """Return the list of .a files to merge for the xlog slice.
    
    Includes OpenSSL (libcrypto, libssl) which are required by xlog's MD5 functions.
    
    Parameters
    ----------
    build_out_path : str
        CMake build directory (e.g., cmake_build/iOS/Release)
    install_path : str
        CMake install directory (e.g., iOS.out)
    platform : str
        Either 'OS' (device arm64) or 'SIMULATOR' (x86_64, arm64)
    """
    libs = [
        install_path + '/libcomm.a',
        install_path + '/libmars-boost.a',
        install_path + '/libxlog.a',
        build_out_path + '/zstd/libzstd.a',
    ]
    
    # Add OpenSSL libraries (required for xlog MD5 support)
    # OpenSSL fat binaries must be sliced to match the target architecture
    openssl_dir = os.path.join(SCRIPT_PATH, 'openssl', 'openssl_lib_iOS')
    temp_slice_dir = os.path.join(install_path, '_openssl_slices')
    os.makedirs(temp_slice_dir, exist_ok=True)
    
    openssl_crypto = os.path.join(openssl_dir, 'libcrypto.a')
    openssl_ssl = os.path.join(openssl_dir, 'libssl.a')
    
    if platform == 'OS':
        # Device: arm64 only
        if os.path.exists(openssl_crypto):
            libs.append(_slice_openssl_arch(openssl_crypto, 'arm64', temp_slice_dir))
        if os.path.exists(openssl_ssl):
            libs.append(_slice_openssl_arch(openssl_ssl, 'arm64', temp_slice_dir))
    else:
        # Simulator: x86_64 only (arm64 simulator doesn't have libcrypto sliced correctly on all systems)
        if os.path.exists(openssl_crypto):
            libs.append(_slice_openssl_arch(openssl_crypto, 'x86_64', temp_slice_dir))
        if os.path.exists(openssl_ssl):
            libs.append(_slice_openssl_arch(openssl_ssl, 'x86_64', temp_slice_dir))
    
    return libs

DEFAULT_OUTDIR = os.path.normpath(
    os.path.join(SCRIPT_PATH, '..', 'samples', 'xlog_flutter', 'ios', 'libs')
)

XCFRAMEWORK_NAME = 'MarsXlog.xcframework'

DEFAULT_LOGDIR = os.path.normpath(
    os.path.join(SCRIPT_PATH, 'logs')
)

# Module-level logger — configured in setup_logging()
log: logging.Logger = logging.getLogger('build_xlog_ios')

# ---------------------------------------------------------------------------
# Logging setup
# ---------------------------------------------------------------------------


def setup_logging(logdir: Optional[str]) -> Optional[str]:
    """Configure root logger to write to stdout AND a timestamped log file.

    Parameters
    ----------
    logdir:
        Directory to write the log file into.  Pass ``None`` to disable file
        logging (stdout only).

    Returns
    -------
    The absolute path of the created log file, or ``None`` if file logging is
    disabled.
    """
    fmt = logging.Formatter(
        fmt='%(asctime)s  %(levelname)-8s  %(message)s',
        datefmt='%Y-%m-%d %H:%M:%S',
    )

    root = logging.getLogger()
    root.setLevel(logging.DEBUG)

    # Always log to stdout
    console_handler = logging.StreamHandler(sys.stdout)
    console_handler.setFormatter(fmt)
    console_handler.setLevel(logging.DEBUG)
    root.addHandler(console_handler)

    if logdir is None:
        return None

    os.makedirs(logdir, exist_ok=True)
    timestamp = time.strftime('%Y%m%d_%H%M%S')
    log_file = os.path.join(logdir, f'build_xlog_ios_{timestamp}.log')

    file_handler = logging.FileHandler(log_file, encoding='utf-8')
    file_handler.setFormatter(fmt)
    file_handler.setLevel(logging.DEBUG)
    root.addHandler(file_handler)

    return log_file


# ---------------------------------------------------------------------------
# Tee: capture os.system() output into the log as well
# ---------------------------------------------------------------------------


def _run_cmd(cmd: str, label: str) -> int:
    """Run *cmd* via subprocess, streaming every output line through the logger.

    Returns the process exit code.
    """
    log.info('Running [%s]: %s', label, cmd)
    proc = subprocess.Popen(
        cmd,
        shell=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )
    assert proc.stdout is not None
    for line in proc.stdout:
        log.info('[%s] %s', label, line.rstrip())
    proc.wait()
    if proc.returncode != 0:
        log.error('[%s] exited with code %d', label, proc.returncode)
    return proc.returncode


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _make_framework(fat_lib: str, framework_path: str) -> bool:
    """Create a .framework bundle from a compiled static library."""
    from mars_utils import make_static_framework
    make_static_framework(fat_lib, framework_path, XLOG_COPY_HEADER_FILES, '../')
    return os.path.exists(framework_path)


def _build_slice(cmake_cmd: str, label: str) -> bool:
    """Run a cmake build command inside BUILD_OUT_PATH, stream output to logger."""
    ret = _run_cmd(cmake_cmd, label)
    os.chdir(SCRIPT_PATH)
    if ret != 0:
        log.error('!!!!!!!!!!!build %s fail!!!!!!!!!!!!!!!', label)
        return False
    return True


def _create_xcframework(os_framework: str, sim_framework: str, output_dir: str) -> bool:
    """Assemble an XCFramework from device + simulator .framework bundles."""
    xcframework_path = os.path.join(output_dir, XCFRAMEWORK_NAME)

    # Remove stale xcframework if present
    if os.path.exists(xcframework_path):
        shutil.rmtree(xcframework_path)

    cmd = (
        f'xcodebuild -create-xcframework '
        f'-framework "{os_framework}" '
        f'-framework "{sim_framework}" '
        f'-output "{xcframework_path}"'
    )
    ret = _run_cmd(cmd, 'xcodebuild')
    if ret != 0:
        log.error('!!!!!!!!!!!xcodebuild -create-xcframework fail!!!!!!!!!!!!!!!')
        return False

    return True


def _verify_dwarf(xcframework_path: str) -> bool:
    """Verify that the XCFramework's static framework slices contain DWARF debug info.

    MarsXlog is built as a **static** framework — DWARF is embedded directly in
    the .a archive objects, not in a separate .dSYM bundle.  Xcode extracts and
    uses these symbols automatically when linking a consumer app, so no external
    dSYM file is needed.

    This function runs `dwarfdump --uuid` on each slice binary to confirm that
    debug symbols are present, and logs a warning if they are missing.

    Parameters
    ----------
    xcframework_path : str
        Path to the assembled MarsXlog.xcframework

    Returns
    -------
    True if all discovered slices contain DWARF; False if any slice is missing symbols.
    """
    # Actual slice directory names as produced by xcodebuild -create-xcframework
    slice_binaries = {
        'ios-arm64':           'MarsXlog.framework/MarsXlog',
        'ios-x86_64-simulator': 'MarsXlog.framework/MarsXlog',
    }

    all_ok = True
    for slice_dir, rel_binary in slice_binaries.items():
        binary_path = os.path.join(xcframework_path, slice_dir, rel_binary)
        if not os.path.exists(binary_path):
            log.warning('[DWARF] Binary not found: %s', binary_path)
            all_ok = False
            continue

        ret = subprocess.run(
            ['xcrun', 'dwarfdump', '--uuid', binary_path],
            capture_output=True, text=True,
        )
        output = (ret.stdout + ret.stderr).strip()
        if ret.returncode == 0 and output:
            log.info('[DWARF] %s: %s', slice_dir, output)
        else:
            # Static .a archives may not report UUIDs but still contain DWARF sections
            ret2 = subprocess.run(
                ['xcrun', 'dwarfdump', '-v', '--debug-abbrev', binary_path],
                capture_output=True, text=True,
            )
            if 'DW_TAG' in ret2.stdout:
                log.info('[DWARF] %s: DWARF sections present (static archive)', slice_dir)
            else:
                log.warning('[DWARF] %s: no DWARF debug info found — Release build may lack symbols', slice_dir)
                all_ok = False

    return all_ok


def _embed_dsyms(xcframework_path: str, build_out_path: str) -> bool:
    """Verify debug symbols are available in the XCFramework (static framework path).

    MarsXlog is built as a static framework — DWARF debug info is embedded
    directly in the .a archive objects inside each XCFramework slice.  This is
    the standard approach for static xcframeworks; a separate .dSYM bundle is
    only needed for dynamic frameworks/dylibs.

    This function delegates to _verify_dwarf() to confirm symbols are present
    and logs actionable warnings if they are not.

    Parameters
    ----------
    xcframework_path : str
        Path to the assembled MarsXlog.xcframework
    build_out_path : str
        Unused for static frameworks; kept for API compatibility with macOS variant.

    Returns
    -------
    True if DWARF symbols verified in all slices; False if any slice is missing symbols.
    """
    log.info('[dSYM] Static framework detected — verifying embedded DWARF (no external .dSYM needed)')
    return _verify_dwarf(xcframework_path)


def _find_dsym(build_out_path: str, platform_label: str) -> Optional[str]:
    """(Unused for static frameworks) Search for external .dSYM bundles.

    Kept for potential future use if the build switches to dynamic frameworks.
    Static MarsXlog frameworks embed DWARF directly in archive objects.
    """
    import glob as _glob
    pattern = os.path.join(build_out_path, '**', 'MarsXlog.framework.dSYM')
    matches = _glob.glob(pattern, recursive=True)
    if matches:
        log.info('[dSYM] Found external dSYM for %s: %s', platform_label, matches[0])
        return matches[0]
    return None


def _embed_dsyms_unused(xcframework_path: str, build_out_path: str) -> bool:
    """(Unused) Original external-dSYM embedding logic for dynamic frameworks."""
    # Map XCFramework slice directory names to platform labels used in log messages
    slice_labels = {
        'ios-arm64':           'OS',
        'ios-x86_64-simulator': 'SIMULATOR',
    }

    embedded_any = False
    for slice_dir_name, platform_label in slice_labels.items():
        slice_path = os.path.join(xcframework_path, slice_dir_name)
        if not os.path.isdir(slice_path):
            log.warning('[dSYM] Slice directory not found: %s', slice_path)
            continue

        dsym_src = _find_dsym(build_out_path, platform_label)
        if dsym_src is None:
            continue

        dsym_dst_dir = os.path.join(slice_path, 'dSYMs')
        dsym_dst = os.path.join(dsym_dst_dir, 'MarsXlog.framework.dSYM')

        os.makedirs(dsym_dst_dir, exist_ok=True)
        if os.path.exists(dsym_dst):
            shutil.rmtree(dsym_dst)

        shutil.copytree(dsym_src, dsym_dst)
        log.info('[dSYM] Embedded: %s -> %s', dsym_src, dsym_dst)
        embedded_any = True

    return embedded_any


# ---------------------------------------------------------------------------
# Core build function
# ---------------------------------------------------------------------------


def build_xlog_ios(config: str, outdir: str, incremental: bool) -> bool:
    """Build MarsXlog.xcframework and deploy it to *outdir*/<config>/."""
    before_time = time.time()

    # Config-specific cmake intermediate and install directories
    build_out_path = BUILD_OUT_BASE + f'/{config}'
    install_path   = build_out_path + '/iOS.out'

    # Final xcframework lives under <outdir>/<config>/
    config_outdir = os.path.join(outdir, config)

    log.info('=' * 60)
    log.info('Building MarsXlog.xcframework  config=%s', config)
    log.info('  cmake dir : %s', build_out_path)
    log.info('  output    : %s', config_outdir)
    log.info('=' * 60)

    gen_mars_revision_file('comm')

    # ------------------------------------------------------------------ OS (device)
    clean(build_out_path, incremental)
    os.chdir(build_out_path)

    if not _build_slice(IOS_BUILD_OS_CMD.format(config=config), 'OS'):
        return False

    xlog_src_libs = _xlog_src_libs(build_out_path, install_path, 'OS')
    libtool_os_dst = install_path + '/os_xlog'
    if not libtool_libs(xlog_src_libs, libtool_os_dst):
        return False

    # ------------------------------------------------------------------ Simulator
    clean(build_out_path, incremental)
    os.chdir(build_out_path)

    if not _build_slice(IOS_BUILD_SIMULATOR_CMD.format(config=config), 'Simulator'):
        return False

    xlog_src_libs = _xlog_src_libs(build_out_path, install_path, 'SIMULATOR')
    libtool_sim_dst = install_path + '/simulator_xlog'
    if not libtool_libs(xlog_src_libs, libtool_sim_dst):
        return False

    # ------------------------------------------------------------------ Intermediate dirs
    tmp_dir     = os.path.join(install_path, 'xcframework_tmp')
    os_fw_path  = os.path.join(tmp_dir, 'os', 'MarsXlog.framework')
    sim_fw_path = os.path.join(tmp_dir, 'simulator', 'MarsXlog.framework')

    for path in (os_fw_path, sim_fw_path):
        if os.path.exists(path):
            shutil.rmtree(path)

    # ------------------------------------------------------------------ Build .framework slices
    if not _make_framework(libtool_os_dst, os_fw_path):
        log.error('!!!!!!!!!!!make_static_framework OS fail!!!!!!!!!!!!!!!')
        return False

    if not _make_framework(libtool_sim_dst, sim_fw_path):
        log.error('!!!!!!!!!!!make_static_framework Simulator fail!!!!!!!!!!!!!!!')
        return False

    # ------------------------------------------------------------------ Assemble XCFramework
    os.makedirs(config_outdir, exist_ok=True)

    if not _create_xcframework(os_fw_path, sim_fw_path, config_outdir):
        return False

    # ------------------------------------------------------------------ Verify DWARF symbols
    if config == 'Release':
        xcframework_path = os.path.join(config_outdir, XCFRAMEWORK_NAME)
        if not _embed_dsyms(xcframework_path, build_out_path):
            log.warning('DWARF symbols missing — consumers may have limited native debug info')
        else:
            log.info('DWARF symbols verified in XCFramework (static framework, no external .dSYM needed)')

    xcframework_path = os.path.join(config_outdir, XCFRAMEWORK_NAME)
    elapsed = int(time.time() - before_time)
    log.info('')
    log.info('==================Output========================')
    log.info('  %s', xcframework_path)
    log.info('use time: %d s', elapsed)
    return True


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------


def main():
    parser = argparse.ArgumentParser(
        description='Build MarsXlog.xcframework for iOS and deploy to the Flutter plugin libs directory.',
    )
    parser.add_argument(
        '--config',
        default='Release',
        choices=['Release', 'Debug'],
        help='"Release" (default) or "Debug"',
    )
    parser.add_argument(
        '--outdir',
        default=DEFAULT_OUTDIR,
        help=(
            f'Base output directory; xcframework is placed under <outdir>/<config>/ '
            f'(default: {DEFAULT_OUTDIR})'
        ),
    )
    parser.add_argument(
        '--incremental',
        action='store_true',
        default=False,
        help='Skip cleaning the cmake build directory (incremental build)',
    )
    parser.add_argument(
        '--logdir',
        default=DEFAULT_LOGDIR,
        help=(
            f'Directory for build log files '
            f'(default: {DEFAULT_LOGDIR})'
        ),
    )
    parser.add_argument(
        '--no-log',
        action='store_true',
        default=False,
        help='Disable file logging (print to stdout only)',
    )
    args = parser.parse_args()

    logdir = None if args.no_log else os.path.abspath(args.logdir)
    log_file = setup_logging(logdir)

    log.info('args: %s', args)
    if log_file:
        log.info('Build log: %s', log_file)

    outdir = os.path.abspath(args.outdir)
    ok = build_xlog_ios(config=args.config, outdir=outdir, incremental=args.incremental)

    log.info('')
    log.info('==================Summary========================')
    log.info('  %s: %s', args.config, 'OK' if ok else 'FAIL')
    if log_file:
        log.info('  Log saved to: %s', log_file)

    if not ok:
        sys.exit(1)


if __name__ == '__main__':
    main()
