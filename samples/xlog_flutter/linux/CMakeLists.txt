# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. You should not increase this version, as doing so will cause
# the plugin to fail to compile for some customers of the plugin.
cmake_minimum_required(VERSION 3.10)

# Project-level configuration.
set(PROJECT_NAME "xlog_flutter")
project(${PROJECT_NAME} LANGUAGES CXX)

# Shared source lives in ../src/
get_filename_component(PLUGIN_LINUX_REAL "${CMAKE_CURRENT_SOURCE_DIR}" REALPATH)
set(PLUGIN_SRC  "${PLUGIN_LINUX_REAL}/../src")
set(INCLUDE_DIR "${PLUGIN_LINUX_REAL}/../include")
set(LIB_DIR     "${PLUGIN_LINUX_REAL}/libs")

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
# Link prebuilt xlog static library
# ---------------------------------------------------------------------------
set(XLOG_LIB "${LIB_DIR}/x64/libxlog.a")
if(EXISTS "${XLOG_LIB}")
  target_link_libraries(xlog_flutter PRIVATE "${XLOG_LIB}")
else()
  message(WARNING
    "xlog prebuilt lib not found: ${XLOG_LIB}\n"
    "Build it with: cd mars && mkdir -p cmake_build/linux && cd cmake_build/linux && cmake ../.. && cmake --build . --target xlog\n"
    "Then copy cmake_build/linux/xlog/libxlog.a to linux/libs/x64/libxlog.a")
endif()

# List of absolute paths to libraries that should be bundled with the plugin.
set(xlog_flutter_bundled_libraries
  $<TARGET_FILE:xlog_flutter>
  PARENT_SCOPE
)
