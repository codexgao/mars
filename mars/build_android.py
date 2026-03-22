#!/usr/bin/env python3
import os
import sys
import glob
import time
import shutil
import platform
import subprocess
import logging

from mars_utils import *

log = logging.getLogger(__name__)


SCRIPT_PATH = os.path.split(os.path.realpath(__file__))[0]

def system_is_windows():
    return platform.system() == 'Windows'

def system_architecture_is64():
    return platform.machine().endswith('64')


if system_is_windows():
    ANDROID_GENERATOR = '-G "Unix Makefiles"'
else:
    ANDROID_GENERATOR = ''

try:
    NDK_ROOT = os.environ['NDK_ROOT']
except KeyError as identifier:
    NDK_ROOT = ''


BUILD_OUT_PATH = 'cmake_build/Android'
ANDROID_LIBS_INSTALL_PATH = BUILD_OUT_PATH + '/'
ANDROID_BUILD_CMD = 'cmake "%s" %s -DANDROID_ABI="%s" ' \
                    '-DCMAKE_BUILD_TYPE=%s -DCMAKE_TOOLCHAIN_FILE=%s/build/cmake/android.toolchain.cmake ' \
                    '-DANDROID_TOOLCHAIN=clang -DANDROID_NDK=%s ' \
                    '-DANDROID_PLATFORM=android-21 ' \
                    '-DANDROID_STL="c++_shared" ' \
                    '&& cmake --build . %s --config %s -- -j8'
ANDROID_SYMBOL_PATH = 'libraries/mars_android_sdk/obj/local/'
ANDROID_LIBS_PATH = 'libraries/mars_android_sdk/libs/'
ANDROID_XLOG_SYMBOL_PATH = 'libraries/mars_xlog_sdk/obj/local/'
ANDROID_XLOG_LIBS_PATH = 'libraries/mars_xlog_sdk/libs/'


ANDROID_STRIP_FILE = {
        'armeabi': NDK_ROOT + '/toolchains/arm-linux-androideabi-4.9/prebuilt/%s/bin/arm-linux-androideabi-strip',
        'armeabi-v7a': NDK_ROOT + '/toolchains/arm-linux-androideabi-4.9/prebuilt/%s/bin/arm-linux-androideabi-strip',
        'x86': NDK_ROOT + '/toolchains/x86-4.9/prebuilt/%s/bin/i686-linux-android-strip',
        'arm64-v8a': NDK_ROOT + '/toolchains/aarch64-linux-android-4.9/prebuilt/%s/bin/aarch64-linux-android-strip',
        'x86_64': NDK_ROOT + '/toolchains/x86_64-4.9/prebuilt/%s/bin/x86_64-linux-android-strip',
         }


ANDROID_STL_FILE = {
        'armeabi': NDK_ROOT + '/sources/cxx-stl/llvm-libc++/libs/armeabi/libc++_shared.so',
        'armeabi-v7a': NDK_ROOT + '/sources/cxx-stl/llvm-libc++/libs/armeabi-v7a/libc++_shared.so',
        'x86': NDK_ROOT + '/sources/cxx-stl/llvm-libc++/libs/x86/libc++_shared.so',
        'arm64-v8a': NDK_ROOT + '/sources/cxx-stl/llvm-libc++/libs/arm64-v8a/libc++_shared.so',
        'x86_64': NDK_ROOT + '/sources/cxx-stl/llvm-libc++/libs/x86_64/libc++_shared.so',
        }


def get_android_strip_cmd(arch):

    system_str = platform.system().lower()
    if (system_architecture_is64()):
        system_str = system_str + '-x86_64'
    else:
        pass

    strip_cmd = ANDROID_STRIP_FILE[arch] %(system_str)
    print('Android strip cmd:%s' %(strip_cmd))
    return strip_cmd


def _find_llvm_tool(tool_name: str, ndk_root: str) -> str:
    """Locate an LLVM tool (llvm-objcopy, llvm-strip) in the NDK toolchain.

    NDK r21+ ships LLVM tools under:
        <ndk_root>/toolchains/llvm/prebuilt/<host>/bin/<tool_name>
    where <host> is e.g. linux-x86_64 or darwin-x86_64.
    On Windows the binary has a .exe extension.
    """
    pattern = os.path.join(
        ndk_root, 'toolchains', 'llvm', 'prebuilt', '*', 'bin', tool_name
    )
    matches = glob.glob(pattern)
    # Also try with .exe suffix on Windows
    if not matches:
        matches = glob.glob(pattern + '.exe')
    if matches:
        return matches[0]
    return ''


def _extract_sym(so_path: str, sym_path: str, ndk_root: str) -> bool:
    """Extract debug symbols from .so into a separate .so.sym file.

    Uses ``llvm-objcopy --only-keep-debug`` to produce a symbols-only binary.
    The original .so is then stripped in-place with ``llvm-strip --strip-all``.

    Parameters
    ----------
    so_path :
        Path to the full (unstripped) .so file.
    sym_path :
        Output path for the extracted symbols file (.so.sym).
    ndk_root :
        NDK root directory (e.g. the value of $ANDROID_NDK_HOME).

    Returns
    -------
    True if symbol extraction succeeded; False on any error (non-fatal).
    """
    llvm_objcopy = _find_llvm_tool('llvm-objcopy', ndk_root)
    if not llvm_objcopy:
        log.warning('[sym] llvm-objcopy not found in NDK: %s', ndk_root)
        return False

    llvm_strip = _find_llvm_tool('llvm-strip', ndk_root)
    if not llvm_strip:
        # Fall back to replacing 'objcopy' with 'strip' in the path
        llvm_strip = llvm_objcopy.replace('llvm-objcopy', 'llvm-strip')

    # Step 1 — extract debug symbols into .so.sym
    result = subprocess.run(
        [llvm_objcopy, '--only-keep-debug', so_path, sym_path],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        log.warning('[sym] llvm-objcopy failed for %s: %s', so_path, result.stderr.strip())
        return False
    log.info('[sym] Extracted symbols: %s', sym_path)

    # Step 2 — strip the original .so in-place
    result = subprocess.run(
        [llvm_strip, '--strip-all', so_path],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        log.warning('[sym] llvm-strip failed for %s: %s', so_path, result.stderr.strip())
        # Non-fatal: symbol extraction succeeded, stripped .so not critical here
    else:
        log.info('[sym] Stripped: %s', so_path)

    return True


def build_android(incremental, arch, target_option='', config='Release'):

    before_time = time.time()

    clean(BUILD_OUT_PATH, incremental)
    os.chdir(BUILD_OUT_PATH)

    build_cmd = ANDROID_BUILD_CMD %(SCRIPT_PATH, ANDROID_GENERATOR, arch, config, NDK_ROOT, NDK_ROOT, target_option, config)
    print("build cmd:" + build_cmd)
    ret = os.system(build_cmd)
    os.chdir(SCRIPT_PATH)

    if 0 != ret:
        print('!!!!!!!!!!!!!!!!!!build fail!!!!!!!!!!!!!!!!!!!!')
        return False

    if len(target_option) > 0:
        symbol_path = ANDROID_XLOG_SYMBOL_PATH
        lib_path = ANDROID_XLOG_LIBS_PATH
    else:
        symbol_path = ANDROID_SYMBOL_PATH
        lib_path = ANDROID_LIBS_PATH

    if not os.path.exists(symbol_path):
        os.makedirs(symbol_path)

    symbol_path = symbol_path + arch
    if os.path.exists(symbol_path):
        shutil.rmtree(symbol_path)

    os.mkdir(symbol_path)


    if not os.path.exists(lib_path):
        os.makedirs(lib_path)

    lib_path = lib_path + arch
    if os.path.exists(lib_path):
        shutil.rmtree(lib_path)

    os.mkdir(lib_path)


    for f in glob.glob(ANDROID_LIBS_INSTALL_PATH + "*.so"):
        shutil.copy(f, symbol_path)
        shutil.copy(f, lib_path)

    # copy stl
    shutil.copy(ANDROID_STL_FILE[arch], symbol_path)
    shutil.copy(ANDROID_STL_FILE[arch], lib_path)


    # For Release builds: extract debug symbols into .so.sym, then strip the .so.
    # We prefer the modern LLVM tools (NDK r21+) over the legacy GCC strip.
    # For Debug builds: keep full debug symbols for direct Android Studio debugging.
    if config == 'Release':
        ndk_root = NDK_ROOT or os.environ.get('ANDROID_NDK_HOME', '')
        use_llvm = bool(ndk_root and _find_llvm_tool('llvm-objcopy', ndk_root))

        for f in glob.glob('%s/*.so' % lib_path):
            if use_llvm:
                sym_file = f + '.sym'
                ok = _extract_sym(f, sym_file, ndk_root)
                if ok:
                    size_kb = os.path.getsize(sym_file) // 1024
                    print('  Symbol file: %s  (%d KB)' % (sym_file, size_kb))
                else:
                    # Fall back to legacy GCC strip if LLVM extraction failed
                    strip_cmd = get_android_strip_cmd(arch)
                    os.system('%s %s' % (strip_cmd, f))
            else:
                # Legacy NDK or NDK_ROOT not set — use old GCC strip toolchain
                strip_cmd = get_android_strip_cmd(arch)
                os.system('%s %s' % (strip_cmd, f))

    print('==================Output========================')
    print('libs(%s): %s' %(config.lower(), lib_path))
    print('symbols(must store permanently): %s' %(symbol_path))


    after_time = time.time()

    print("use time:%d s" % (int(after_time - before_time)))
    return True

def main(incremental, archs, target_option='', tag='', config='Release'):
    if not check_ndk_env():
        return

    gen_mars_revision_file(SCRIPT_PATH + '/comm', tag)

    # if os.path.exists(ANDROID_LIBS_PATH):
    #     shutil.rmtree(ANDROID_LIBS_PATH)

    # if os.path.exists(ANDROID_SYMBOL_PATH):
    #     shutil.rmtree(ANDROID_SYMBOL_PATH)

    for arch in archs:
        if not build_android(incremental, arch, target_option, config):
            return

if __name__ == '__main__':

    while True:
        if len(sys.argv) >= 3:
            archs = sys.argv[2:]
            main(False, archs, tag=sys.argv[1])
            break
        else:
            archs = {'armeabi-v7a', 'arm64-v8a'}
            num = input('Enter menu:\n1. Clean && build mars (Release).\n2. Build incrementally mars (Release).\n3. Clean && build xlog (Release).\n4. Clean && build xlog (Debug).\n5. Exit\n')
            if num == '1':
                main(False, archs)
                break
            elif num == '2':
                main(True, archs)
                break
            elif num == '3':
                main(False, archs, '--target libzstd_static marsxlog')
                break
            elif num == '4':
                main(False, archs, '--target libzstd_static marsxlog', config='Debug')
                break
            elif num == '5':
                break
            else:
                main(False, archs)
                break


