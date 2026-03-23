cmake_minimum_required(VERSION 3.10)
project(xlog_native_bridge)

add_library(xlog_native_bridge SHARED xlog_native_bridge.cpp)

# libxlog.so 预编译库路径
# 从 cpp/ 目录向上 7 层到 samples/xlog_flutter/，再进入 android/src/main/jniLibs/
# 构建前需先运行：
#   cd mars/xlog
#   python build_android.py --config Release --output-dir ../../samples/xlog_flutter/android/src/main/jniLibs --arch armeabi-v7a arm64-v8a
set(XLOG_LIB_PATH "${CMAKE_SOURCE_DIR}/../../../../../../../android/src/main/jniLibs/${ANDROID_ABI}/libxlog.so")
add_library(xlog SHARED IMPORTED)
set_target_properties(xlog PROPERTIES
    IMPORTED_LOCATION "${XLOG_LIB_PATH}"
)

# xlog C API 头文件路径
# 从 cpp/ 目录向上 8 层到仓库根目录，再进入 mars/xlog/capi/
include_directories("${CMAKE_SOURCE_DIR}/../../../../../../../../mars/xlog/capi")

target_link_libraries(xlog_native_bridge
    xlog
    log
)
