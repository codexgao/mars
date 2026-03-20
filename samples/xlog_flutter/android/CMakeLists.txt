cmake_minimum_required(VERSION 3.10)

project(xlog_flutter_library VERSION 0.0.1 LANGUAGES CXX)

# Resolve real path so symlink traversal (Flutter .plugin_symlinks/) works correctly.
get_filename_component(PLUGIN_ANDROID_REAL "${CMAKE_CURRENT_SOURCE_DIR}" REALPATH)
set(PLUGIN_SRC  "${PLUGIN_ANDROID_REAL}/../src")
set(INCLUDE_DIR "${PLUGIN_ANDROID_REAL}/../include")
if(CMAKE_BUILD_TYPE STREQUAL "Debug")
  set(LIB_DIR "${PLUGIN_ANDROID_REAL}/libs/Debug")
else()
  set(LIB_DIR "${PLUGIN_ANDROID_REAL}/libs/Release")
endif()

add_library(xlog_flutter SHARED
  "${PLUGIN_SRC}/xlog_flutter.cpp"
)

target_include_directories(xlog_flutter PRIVATE "${INCLUDE_DIR}" "${PLUGIN_SRC}")

set_target_properties(xlog_flutter PROPERTIES
  PUBLIC_HEADER "${PLUGIN_SRC}/xlog_flutter.h"
  OUTPUT_NAME "xlog_flutter"
  CXX_STANDARD 17
  CXX_STANDARD_REQUIRED YES
)

target_compile_definitions(xlog_flutter PUBLIC DART_SHARED_LIB)

# ---------------------------------------------------------------------------
# Link prebuilt xlog shared library
# ---------------------------------------------------------------------------
set(XLOG_SO "${LIB_DIR}/${ANDROID_ABI}/libmarsxlog.so")
if(EXISTS "${XLOG_SO}")
  add_library(marsxlog SHARED IMPORTED)
  set_target_properties(marsxlog PROPERTIES
    IMPORTED_LOCATION "${XLOG_SO}"
  )
  target_link_libraries(xlog_flutter PRIVATE marsxlog log z)
else()
  message(FATAL_ERROR
    "xlog prebuilt lib not found: ${XLOG_SO}\n"
    "Build it with:\n"
    "  set NDK_ROOT=D:\\Envs\\Android\\Sdk\\ndk\\<version>\n"
    "  cd mars && python build_android.py\n"
    "    option 3 -> Release -> copy to android/libs/Release/<ABI>/\n"
    "    option 4 -> Debug   -> copy to android/libs/Debug/<ABI>/")
endif()
