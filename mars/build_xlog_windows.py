#!/usr/bin/env python3
"""Build xlog.dll for Windows and deploy to the Flutter plugin's libs directory.

Usage:
    python build_xlog_windows.py [--config Release|Debug|all] [--outdir PATH] [--incremental]

Defaults:
    --config     Release
    --outdir     ../samples/xlog_flutter/windows/libs/x64
    --incremental  False (clean build)

VS environment detection order:
    1. MSVC_TOOLS_PATH env var  (same as build_windows.py)
    2. vswhere.exe auto-discovery (installed with Visual Studio)
"""

import os
import sys
import time
import shutil
import argparse
import subprocess
from typing import Optional

from mars_utils import gen_mars_revision_file, clean_windows, check_vs_env

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

SCRIPT_PATH = os.path.split(os.path.realpath(__file__))[0]

BUILD_OUT_PATH = 'cmake_build/Windows'
# cmake install puts DLL/lib/pdb directly into Windows.out/ (not into win/)
WIN_INSTALL_DIR = BUILD_OUT_PATH + '/Windows.out/'

WIN_BUILD_CMD_SHARED = (
    'cmake ../.. -G "Visual Studio 17 2022" -A x64 '
    '-DMARS_USE_DYNAMIC_CRT=ON -DXLOG_BUILD_SHARED=ON '
    '&& cmake --build . --target install --config %s'
)

# Artifacts produced by the DLL build that get deployed to the Flutter plugin.
DEPLOY_ARTIFACTS = ['xlog.dll', 'xlog.lib', 'xlog.pdb']

DEFAULT_OUTDIR = os.path.normpath(
    os.path.join(SCRIPT_PATH, '..', 'samples', 'xlog_flutter', 'windows', 'libs', 'x64')
)

# ---------------------------------------------------------------------------
# VS environment detection
# ---------------------------------------------------------------------------

def _find_vsdevcmd_via_vswhere() -> Optional[str]:
    """Use vswhere.exe to locate VsDevCmd.bat for the latest VS installation."""
    vswhere = os.path.join(
        os.environ.get('ProgramFiles(x86)', 'C:\\Program Files (x86)'),
        'Microsoft Visual Studio', 'Installer', 'vswhere.exe',
    )
    if not os.path.isfile(vswhere):
        return None
    try:
        result = subprocess.run(
            [vswhere, '-latest', '-property', 'installationPath'],
            capture_output=True, text=True, timeout=10,
        )
        install_path = result.stdout.strip()
        if not install_path:
            return None
        vsdevcmd = os.path.join(install_path, 'Common7', 'Tools', 'VsDevCmd.bat')
        return vsdevcmd if os.path.isfile(vsdevcmd) else None
    except Exception:
        return None


def setup_vs_env() -> bool:
    """Locate and initialise the VS Developer environment.

    Order:
      1. MSVC_TOOLS_PATH environment variable (same as build_windows.py)
      2. vswhere.exe auto-discovery
    """
    # --- Option 1: explicit env var (compatible with build_windows.py) ---
    msvc_tools = os.environ.get('MSVC_TOOLS_PATH')
    if msvc_tools:
        vsdevcmd = os.path.join(msvc_tools, 'VsDevCmd.bat')
        if os.path.isfile(vsdevcmd):
            print(f'Using VS env from MSVC_TOOLS_PATH: {vsdevcmd}')
            return check_vs_env(f'"{vsdevcmd}"')
        else:
            print(f'Warning: MSVC_TOOLS_PATH is set but VsDevCmd.bat not found at: {vsdevcmd}')

    # --- Option 2: vswhere auto-discovery ---
    vsdevcmd = _find_vsdevcmd_via_vswhere()
    if vsdevcmd:
        print(f'Auto-detected VS env via vswhere: {vsdevcmd}')
        return check_vs_env(f'"{vsdevcmd}"')

    # --- Neither worked ---
    print('ERROR: Could not locate Visual Studio Developer environment.')
    print('  Set MSVC_TOOLS_PATH to your VS Common7/Tools directory, e.g.:')
    print('    set MSVC_TOOLS_PATH=C:\\Program Files\\Microsoft Visual Studio\\2022\\Professional\\Common7\\Tools')
    return False


# ---------------------------------------------------------------------------
# Build logic
# ---------------------------------------------------------------------------

def build_xlog(config: str, outdir: str, incremental: bool) -> bool:
    """Build xlog DLL for one configuration and deploy artifacts to *outdir*/<config>/."""
    before_time = time.time()
    print(f'\n{"="*60}')
    print(f'Building xlog DLL  config={config}  outdir={outdir}')
    print(f'{"="*60}')

    gen_mars_revision_file('comm')

    build_out_abs = os.path.join(SCRIPT_PATH, BUILD_OUT_PATH)
    clean_windows(build_out_abs, incremental)
    os.chdir(build_out_abs)

    build_cmd = WIN_BUILD_CMD_SHARED % config
    print('build cmd: ' + build_cmd)
    ret: int = os.system(build_cmd)
    os.chdir(SCRIPT_PATH)

    if ret != 0:
        print('!!!!!!!!!!!!!!!!!!build fail!!!!!!!!!!!!!!!!!!!!')
        return False

    # Deploy artifacts to <outdir>/<Config>/
    dest_dir = os.path.join(outdir, config)
    os.makedirs(dest_dir, exist_ok=True)

    all_ok = True
    for name in DEPLOY_ARTIFACTS:
        src = os.path.normpath(os.path.join(SCRIPT_PATH, WIN_INSTALL_DIR, name))
        dst = os.path.join(dest_dir, name)
        if os.path.exists(src):
            shutil.copy(src, dst)
            size_kb = os.path.getsize(dst) // 1024
            print(f'  Deployed {name} -> {dst}  ({size_kb} KB)')
        else:
            print(f'  Warning: artifact not found: {src}')
            if name == 'xlog.dll':
                all_ok = False  # DLL is mandatory; .pdb is optional

    elapsed = int(time.time() - before_time)
    print(f'\n==================Output========================')
    print(f'  {dest_dir}')
    print(f'use time: {elapsed} s')
    return all_ok


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description='Build xlog.dll for Windows and deploy to the Flutter plugin libs directory.',
    )
    parser.add_argument(
        '--config',
        default='Release',
        choices=['Release', 'Debug', 'all'],
        help='"Release" (default), "Debug", or "all" to build both',
    )
    parser.add_argument(
        '--outdir',
        default=DEFAULT_OUTDIR,
        help=f'Output root directory (default: {DEFAULT_OUTDIR}). '
             'Artifacts are written to <outdir>/Release/ or <outdir>/Debug/.',
    )
    parser.add_argument(
        '--incremental',
        action='store_true',
        default=False,
        help='Skip cleaning the cmake build directory (incremental build)',
    )
    args = parser.parse_args()
    print(args)

    if not setup_vs_env():
        sys.exit(1)

    configs = ['Release', 'Debug'] if args.config == 'all' else [args.config]
    outdir = os.path.abspath(args.outdir)

    results = {}
    for cfg in configs:
        results[cfg] = build_xlog(config=cfg, outdir=outdir, incremental=args.incremental)

    # Summary
    print('\n==================Summary========================')
    all_passed = True
    for cfg, ok in results.items():
        status = 'OK' if ok else 'FAIL'
        print(f'  {cfg}: {status}')
        if not ok:
            all_passed = False

    if not all_passed:
        sys.exit(1)


if __name__ == '__main__':
    main()
