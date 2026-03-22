#!/usr/bin/env python3
"""Build MarsXlog.xcframework for macOS and deploy to the Flutter plugin's libs directory.

Usage:
    python build_xlog_mac.py [--config Release|Debug] [--outdir PATH] [--incremental]
                             [--logdir PATH] [--no-log]

Defaults:
    --config       Release
    --outdir       ../samples/xlog_flutter/macos/libs
    --incremental  False (clean build)
    --logdir       ../logs
    --no-log       False (logging enabled)

Output:
    <outdir>/Release/MarsXlog.xcframework   (or Debug/)
      └── macos-arm64_x86_64/
          └── MarsXlog.framework/

Log file:
    <logdir>/build_xlog_mac_<timestamp>.log
"""

import os
import sys
import time
import shutil
import argparse
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
BUILD_OUT_BASE = 'cmake_build/OSX'

# CMake commands for macOS — no toolchain file needed, use system cmake directly
# {config} and architecture injected at runtime
_OSX_CMAKE_BASE = (
    'cmake ../../.. '
    '-DCMAKE_BUILD_TYPE={config} '
    '-DENABLE_ARC=0 '
    '-DENABLE_BITCODE=0 '
    '-DCMAKE_OSX_ARCHITECTURES="{arch}"'
)

OSX_BUILD_ARM_CMD = _OSX_CMAKE_BASE + ' && make -j8 && make install'
OSX_BUILD_X86_CMD = _OSX_CMAKE_BASE + ' && make -j8 && make install'

DEFAULT_OUTDIR = os.path.normpath(
    os.path.join(SCRIPT_PATH, '..', 'samples', 'xlog_flutter', 'macos', 'libs')
)

XCFRAMEWORK_NAME = 'MarsXlog.xcframework'

DEFAULT_LOGDIR = os.path.normpath(
    os.path.join(SCRIPT_PATH, 'logs')
)

# Module-level logger — configured in setup_logging()
log: logging.Logger = logging.getLogger('build_xlog_mac')

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
    log_file = os.path.join(logdir, f'build_xlog_mac_{timestamp}.log')

    file_handler = logging.FileHandler(log_file, encoding='utf-8')
    file_handler.setFormatter(fmt)
    file_handler.setLevel(logging.DEBUG)
    root.addHandler(file_handler)

    return log_file


# ---------------------------------------------------------------------------
# Subprocess helper
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


def _slice_openssl_arch(lib_path: str, arch: str, temp_dir: str) -> str:
    """Extract single-architecture slice from a fat binary using lipo.

    Parameters
    ----------
    lib_path : str
        Path to fat binary (e.g. libcrypto.a with arm64+x86_64)
    arch : str
        Target architecture ('arm64' or 'x86_64')
    temp_dir : str
        Directory to place the sliced binary

    Returns
    -------
    Path to sliced .a file, or original path if lipo fails.
    """
    if not os.path.exists(lib_path):
        return lib_path

    basename = os.path.basename(lib_path)
    output_path = os.path.join(temp_dir, f'{arch}_{basename}')

    cmd = f'lipo "{lib_path}" -thin {arch} -output "{output_path}"'
    ret = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    if ret.returncode != 0:
        log.warning('Failed to slice %s for %s: %s', basename, arch, ret.stderr)
        return lib_path

    return output_path


def _xlog_src_libs(build_out_path: str, install_path: str, arch: str) -> list:
    """Return the list of .a files to merge for one architecture slice.

    Parameters
    ----------
    build_out_path : str
        CMake build directory (e.g., cmake_build/OSX/Release)
    install_path : str
        CMake install directory (e.g., cmake_build/OSX/Release/Darwin.out)
    arch : str
        Target architecture ('arm64' or 'x86_64')
    """
    libs = [
        install_path + '/libcomm.a',
        install_path + '/libmars-boost.a',
        install_path + '/libxlog.a',
        build_out_path + '/zstd/libzstd.a',
    ]

    # Add OpenSSL libraries (required for xlog MD5 support)
    openssl_dir = os.path.join(SCRIPT_PATH, 'openssl', 'openssl_lib_osx')
    temp_slice_dir = os.path.join(install_path, '_openssl_slices')
    os.makedirs(temp_slice_dir, exist_ok=True)

    openssl_crypto = os.path.join(openssl_dir, 'libcrypto.a')
    openssl_ssl = os.path.join(openssl_dir, 'libssl.a')

    if os.path.exists(openssl_crypto):
        libs.append(_slice_openssl_arch(openssl_crypto, arch, temp_slice_dir))
    if os.path.exists(openssl_ssl):
        libs.append(_slice_openssl_arch(openssl_ssl, arch, temp_slice_dir))

    return libs


def _make_framework(fat_lib: str, framework_path: str) -> bool:
    """Create a .framework bundle from a compiled static library."""
    from mars_utils import make_static_framework
    make_static_framework(fat_lib, framework_path, XLOG_COPY_HEADER_FILES, '../')
    return os.path.exists(framework_path)


def _build_arch(config: str, arch: str, build_out_path: str, label: str) -> bool:
    """Clean, cmake configure, build, and install for one architecture."""
    clean(build_out_path)
    os.chdir(build_out_path)

    cmake_cmd = OSX_BUILD_ARM_CMD.format(config=config, arch=arch)
    ret = _run_cmd(cmake_cmd, label)
    os.chdir(SCRIPT_PATH)
    if ret != 0:
        log.error('!!!!!!!!!!!build %s fail!!!!!!!!!!!!!!!', label)
        return False
    return True


def _create_xcframework(framework_path: str, output_dir: str) -> bool:
    """Wrap a single .framework into an XCFramework.

    macOS does not need a device/simulator split; one framework is sufficient.
    """
    xcframework_path = os.path.join(output_dir, XCFRAMEWORK_NAME)

    # Remove stale xcframework if present
    if os.path.exists(xcframework_path):
        shutil.rmtree(xcframework_path)

    cmd = (
        f'xcodebuild -create-xcframework '
        f'-framework "{framework_path}" '
        f'-output "{xcframework_path}"'
    )
    ret = _run_cmd(cmd, 'xcodebuild')
    if ret != 0:
        log.error('!!!!!!!!!!!xcodebuild -create-xcframework fail!!!!!!!!!!!!!!!')
        return False

    return True


# ---------------------------------------------------------------------------
# Core build function
# ---------------------------------------------------------------------------


def build_xlog_mac(config: str, outdir: str, incremental: bool) -> bool:
    """Build MarsXlog.xcframework for macOS and deploy it to *outdir*/<config>/."""
    before_time = time.time()

    # Config-specific cmake intermediate and install directories
    build_out_path = BUILD_OUT_BASE + f'/{config}'
    install_path   = build_out_path + '/Darwin.out'

    # Final xcframework lives under <outdir>/<config>/
    config_outdir = os.path.join(outdir, config)

    log.info('=' * 60)
    log.info('Building MarsXlog.xcframework for macOS  config=%s', config)
    log.info('  cmake dir : %s', build_out_path)
    log.info('  output    : %s', config_outdir)
    log.info('=' * 60)

    gen_mars_revision_file('comm')

    # ------------------------------------------------------------------ arm64 slice
    if not _build_arch(config, 'arm64', build_out_path, 'arm64'):
        return False

    libtool_arm_dst = install_path + '/arm64_xlog'
    arm_src_libs = _xlog_src_libs(build_out_path, install_path, 'arm64')
    if not libtool_libs(arm_src_libs, libtool_arm_dst):
        return False

    # ------------------------------------------------------------------ x86_64 slice
    if not _build_arch(config, 'x86_64', build_out_path, 'x86_64'):
        return False

    libtool_x86_dst = install_path + '/x86_64_xlog'
    x86_src_libs = _xlog_src_libs(build_out_path, install_path, 'x86_64')
    if not libtool_libs(x86_src_libs, libtool_x86_dst):
        return False

    # ------------------------------------------------------------------ lipo fat binary
    lipo_dst = install_path + '/fat_xlog'
    if not lipo_libs([libtool_arm_dst, libtool_x86_dst], lipo_dst):
        return False

    # ------------------------------------------------------------------ Build .framework
    tmp_dir = os.path.join(install_path, 'xcframework_tmp')
    fw_path = os.path.join(tmp_dir, 'MarsXlog.framework')
    if os.path.exists(fw_path):
        shutil.rmtree(fw_path)

    if not _make_framework(lipo_dst, fw_path):
        log.error('!!!!!!!!!!!make_static_framework fail!!!!!!!!!!!!!!!')
        return False

    # ------------------------------------------------------------------ Assemble XCFramework
    os.makedirs(config_outdir, exist_ok=True)

    if not _create_xcframework(fw_path, config_outdir):
        return False

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
        description='Build MarsXlog.xcframework for macOS and deploy to the Flutter plugin libs directory.',
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
    ok = build_xlog_mac(config=args.config, outdir=outdir, incremental=args.incremental)

    log.info('')
    log.info('==================Summary========================')
    log.info('  %s: %s', args.config, 'OK' if ok else 'FAIL')
    if log_file:
        log.info('  Log saved to: %s', log_file)

    if not ok:
        sys.exit(1)


if __name__ == '__main__':
    main()
