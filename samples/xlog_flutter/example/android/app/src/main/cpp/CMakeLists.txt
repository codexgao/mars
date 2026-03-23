cmake_minimum_required(VERSION 3.10)
project(xlog_native_bridge)

add_library(xlog_native_bridge SHARED xlog_native_bridge.cpp)

add_library(xlog SHARED IMPORTED)
set_target_properties(xlog PROPERTIES
    IMPORTED_LOCATION "${CMAKE_SOURCE_DIR}/../../../../../../../android/src/main/jniLibs/${ANDROID_ABI}/libxlog.so"
)

include_directories("${CMAKE_SOURCE_DIR}/../../../../../../../../mars/xlog/capi")

target_link_libraries(xlog_native_bridge
    xlog
    log
)
