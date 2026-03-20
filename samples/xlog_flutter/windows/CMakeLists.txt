# The Flutter tooling requires that developers have a version of Visual Studio
# installed that includes CMake 3.14 or later. You should not increase this
# version, as doing so will cause the plugin to fail to compile for some
# customers of the plugin.
cmake_minimum_required(VERSION 3.14)

# Project-level configuration.
set(PROJECT_NAME "xlog_flutter")
project(${PROJECT_NAME} LANGUAGES CXX)

# Shared source lives in ../src/ (no separate CMakeLists.txt needed there).
# Resolve real path so symlink traversal (Flutter .plugin_symlinks/) works correctly.
get_filename_component(PLUGIN_WIN_REAL "${CMAKE_CURRENT_SOURCE_DIR}" REALPATH)
set(PLUGIN_SRC  "${PLUGIN_WIN_REAL}/../src")
set(INCLUDE_DIR "${PLUGIN_WIN_REAL}/../include")
set(WIN_SRC_DIR "${PLUGIN_WIN_REAL}/src")
set(LIB_DIR     "${PLUGIN_WIN_REAL}/libs")

add_library(xlog_flutter SHARED
  "${PLUGIN_SRC}/xlog_flutter.cpp"
  # Windows POSIX-compat shim: provides gettimeofday() used by xlog_flutter.cpp
  "${WIN_SRC_DIR}/sys/time.c"
)

# WIN_SRC_DIR is listed first so <sys/time.h> resolves to the local shim
# before any system paths; INCLUDE_DIR provides appender.h / xlogger/*.h.
target_include_directories(xlog_flutter PRIVATE
  "${WIN_SRC_DIR}"
  "${INCLUDE_DIR}"
  "${PLUGIN_SRC}"
)

set_target_properties(xlog_flutter PROPERTIES
  PUBLIC_HEADER "${PLUGIN_SRC}/xlog_flutter.h"
  OUTPUT_NAME "xlog_flutter"
  CXX_STANDARD 17
  CXX_STANDARD_REQUIRED YES
)

target_compile_definitions(xlog_flutter PUBLIC DART_SHARED_LIB)

# ---------------------------------------------------------------------------
# Link prebuilt xlog DLL (import lib) and bundle the DLL with the plugin
# ---------------------------------------------------------------------------
# xlog is built as a DLL with MARS_USE_DYNAMIC_CRT=ON, so it uses /MDd (Debug)
# or /MD (Release) — matching Flutter's default CRT for each configuration.
# All dependencies (comm, boost, zstd, openssl) are statically linked into
# xlog.dll, so only xlog.lib (import lib) and xlog.dll are needed here.
#
# To rebuild:
#   cd mars && python build_windows.py --xlog --config Release
#   copy cmake_build/Windows/Windows.out/win/xlog.dll  -> windows/libs/x64/Release/xlog.dll
#   copy cmake_build/Windows/Windows.out/win/xlog.lib  -> windows/libs/x64/Release/xlog.lib
#   copy cmake_build/Windows/Windows.out/win/xlog.pdb  -> windows/libs/x64/Release/xlog.pdb  (optional)
#
#   cd mars && python build_windows.py --xlog --config Debug
#   copy cmake_build/Windows/Windows.out/win/xlog.dll  -> windows/libs/x64/Debug/xlog.dll
#   copy cmake_build/Windows/Windows.out/win/xlog.lib  -> windows/libs/x64/Debug/xlog.lib
#   copy cmake_build/Windows/Windows.out/win/xlog.pdb  -> windows/libs/x64/Debug/xlog.pdb  (optional)

set(XLOG_IMPORT_LIB
    "$<$<CONFIG:Debug>:${LIB_DIR}/x64/Debug/xlog.lib>$<$<NOT:$<CONFIG:Debug>>:${LIB_DIR}/x64/Release/xlog.lib>")
set(XLOG_DLL
    "$<$<CONFIG:Debug>:${LIB_DIR}/x64/Debug/xlog.dll>$<$<NOT:$<CONFIG:Debug>>:${LIB_DIR}/x64/Release/xlog.dll>")

target_link_libraries(xlog_flutter PRIVATE "${XLOG_IMPORT_LIB}")

# List of absolute paths to libraries that should be bundled with the plugin.
# xlog.dll must be shipped alongside xlog_flutter.dll so the loader can find it.
set(xlog_flutter_bundled_libraries
  $<TARGET_FILE:xlog_flutter>
  "${XLOG_DLL}"
  PARENT_SCOPE
)
