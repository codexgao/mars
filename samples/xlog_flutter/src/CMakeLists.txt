# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. You should not increase this version, as doing so will cause
# the plugin to fail to compile for some customers of the plugin.
cmake_minimum_required(VERSION 3.10)

project(xlog_flutter_plugin LANGUAGES C)

# Resolve real path — Flutter uses symlinks for plugin references.
get_filename_component(PLUGIN_DIR "${CMAKE_CURRENT_SOURCE_DIR}" REALPATH)

# ---- Platform Detection ----
if(ANDROID)
    # Android: Use prebuilt libxlog.so
    # Build with:
    #   python mars/xlog/build_android.py --config Release --output-dir samples/xlog_flutter/android/src/main/jniLibs --arch armeabi-v7a arm64-v8a
    #   python mars/xlog/build_android.py --config Debug --output-dir samples/xlog_flutter/android/src/debug/jniLibs --arch armeabi-v7a arm64-v8a

    if(CMAKE_BUILD_TYPE STREQUAL "Debug" AND EXISTS "${PLUGIN_DIR}/../android/src/debug/jniLibs/${ANDROID_ABI}/libxlog.so")
        set(XLOG_LIBS_DIR "${PLUGIN_DIR}/../android/src/debug/jniLibs/${ANDROID_ABI}")
    else()
        set(XLOG_LIBS_DIR "${PLUGIN_DIR}/../android/src/main/jniLibs/${ANDROID_ABI}")
    endif()

    # Create an imported library target for the prebuilt xlog
    add_library(xlog SHARED IMPORTED GLOBAL)
    set_target_properties(xlog PROPERTIES
        IMPORTED_LOCATION "${XLOG_LIBS_DIR}/libxlog.so"
    )

    # Expose headers so consumers can #include "xlog_capi.h"
    target_include_directories(xlog INTERFACE
        "${PLUGIN_DIR}/../windows/include"
    )

    # Create a dummy library (required by Flutter FFI plugin structure)
    # The actual xlog functions are called via FFI from Dart, not from this library
    add_library(xlog_flutter SHARED
        "dummy.c"
    )

    target_link_libraries(xlog_flutter
        xlog
        log  # Android log library
    )

    # Bundle the shared libraries
    set(xlog_flutter_bundled_libraries
        "${XLOG_LIBS_DIR}/libxlog.so"
        "${XLOG_LIBS_DIR}/libc++_shared.so"
        PARENT_SCOPE
    )

else()
    # Other platforms (Windows, macOS, Linux, iOS):
    # The Flutter app loads xlog.dll/libxlog.so at runtime via DynamicLibrary.open()
    # No compilation needed here.

    # Create a dummy library for non-Android platforms
    add_library(xlog_flutter SHARED
        "dummy.c"
    )

endif()

target_compile_definitions(xlog_flutter PUBLIC DART_SHARED_LIB)
