cmake_minimum_required (VERSION 3.6)

set(CMAKE_INSTALL_PREFIX "${CMAKE_BINARY_DIR}" CACHE PATH "Installation directory" FORCE)
message(STATUS "CMAKE_INSTALL_PREFIX=${CMAKE_INSTALL_PREFIX}")

project (xlog)


set(SELF_LIBS_OUT ${CMAKE_SYSTEM_NAME}.out)


include(../comm/utils.cmake)
include(../comm/CMakeExtraFlags.txt)

include_directories(.)
include_directories(src)
include_directories(..)
include_directories(../..)
include_directories(../comm)
include_directories(../comm/xlogger)
include_directories(../crypt)
include_directories(../../..)
include_directories(../crypt/micro-ecc-master)


file(GLOB SELF_TEMP_SRC_FILES RELATIVE ${PROJECT_SOURCE_DIR} src/*.cc src/*.h)
source_group(src FILES ${SELF_TEMP_SRC_FILES})
list(APPEND SELF_SRC_FILES ${SELF_TEMP_SRC_FILES})


file(GLOB SELF_TEMP_SRC_FILES RELATIVE ${PROJECT_SOURCE_DIR} crypt/*.cc crypt/*.h)
source_group(crypt FILES ${SELF_TEMP_SRC_FILES})
list(APPEND SELF_SRC_FILES ${SELF_TEMP_SRC_FILES})

file(GLOB SELF_TEMP_SRC_FILES RELATIVE ${PROJECT_SOURCE_DIR} crypt/micro-ecc-master/*.c crypt/micro-ecc-master/*.h)
source_group(crypt\\micro-ecc-master FILES ${SELF_TEMP_SRC_FILES})
list(APPEND SELF_SRC_FILES ${SELF_TEMP_SRC_FILES})



if(MSVC)
    add_definitions(/FI"../../comm/projdef.h")

    include_directories(../comm/windows)
    include_directories(../comm/windows/zlib)

elseif(APPLE)
    file(GLOB SELF_TEMP_SRC_FILES RELATIVE ${PROJECT_SOURCE_DIR} objc/*.mm)
    source_group(objc FILES ${SELF_TEMP_SRC_FILES})
    list(APPEND SELF_SRC_FILES ${SELF_TEMP_SRC_FILES})
elseif(ANDROID)
    file(GLOB SELF_ANDROID_SRC_FILES RELATIVE ${PROJECT_SOURCE_DIR}
            ../comm/xlogger/xloggerbase.c
            ../comm/xlogger/xlogger.cc
            jni/*.cc
            ../mk_template/JNI_OnLoad.cpp)
        
    list(APPEND SELF_SRC_FILES ${SELF_ANDROID_SRC_FILES})

    get_filename_component(EXPORT_EXP_FILE jni/export.exp ABSOLUTE)
    set (CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -Wl,--version-script=${EXPORT_EXP_FILE}")
elseif(OHOS)
    file(GLOB SELF_TEMP_SRC_FILES RELATIVE ${PROJECT_SOURCE_DIR} ohos/*.cc)
    list(APPEND SELF_SRC_FILES ${SELF_TEMP_SRC_FILES})
elseif(UNIX)
    file(GLOB SELF_TEMP_SRC_FILES RELATIVE ${PROJECT_SOURCE_DIR} unix/*.cc)
    list(APPEND SELF_SRC_FILES ${SELF_TEMP_SRC_FILES})
endif()

# add_library(${PROJECT_NAME} STATIC ${SELF_SRC_FILES})
# install(TARGETS ${PROJECT_NAME} ARCHIVE DESTINATION ${SELF_LIBS_OUT})

BuildWithUnitTest("${PROJECT_NAME}" "${SELF_SRC_FILES}")

# ---------------------------------------------------------------------------
# Windows DLL target (opt-in via -DXLOG_BUILD_SHARED=ON)
# ---------------------------------------------------------------------------
if(MSVC AND XLOG_BUILD_SHARED)
    # Build source list without unittest files (gtest not available in DLL builds)
    set(XLOG_SHARED_SRC_FILES ${SELF_SRC_FILES})
    list(FILTER XLOG_SHARED_SRC_FILES EXCLUDE REGEX ".*_unittest\\.cc$")

    add_library(xlog_shared SHARED ${XLOG_SHARED_SRC_FILES})

    set_target_properties(xlog_shared PROPERTIES
        OUTPUT_NAME "xlog"
        PDB_NAME    "xlog"
        WINDOWS_EXPORT_ALL_SYMBOLS OFF
    )

    # Use LINK_FLAGS to specify .def file (compatible with CMake 3.6+)
    set_target_properties(xlog_shared PROPERTIES
        LINK_FLAGS "/DEF:\"${CMAKE_CURRENT_SOURCE_DIR}/xlog_windows.def\""
    )

    target_include_directories(xlog_shared PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${CMAKE_CURRENT_SOURCE_DIR}/src
        ${CMAKE_CURRENT_SOURCE_DIR}/..
        ${CMAKE_CURRENT_SOURCE_DIR}/../..
        ${CMAKE_CURRENT_SOURCE_DIR}/../comm
        ${CMAKE_CURRENT_SOURCE_DIR}/../comm/xlogger
        ${CMAKE_CURRENT_SOURCE_DIR}/../comm/windows
        ${CMAKE_CURRENT_SOURCE_DIR}/../comm/windows/zlib
        ${CMAKE_CURRENT_SOURCE_DIR}/../crypt
        ${CMAKE_CURRENT_SOURCE_DIR}/../crypt/micro-ecc-master
        ${CMAKE_CURRENT_SOURCE_DIR}/../../..
    )

    # _LIB is injected globally by utils.cmake; remove it for the SHARED target
    # (xlog/comm headers don't use _LIB, this is defensive)
    get_target_property(_existing_defs xlog_shared COMPILE_DEFINITIONS)
    if(_existing_defs)
        list(REMOVE_ITEM _existing_defs "_LIB")
        set_target_properties(xlog_shared PROPERTIES COMPILE_DEFINITIONS "${_existing_defs}")
    endif()
    target_compile_definitions(xlog_shared PRIVATE XLOG_BUILDING_DLL)

    # Link: comm static lib + boost + zstd + openssl(x64) + windows system libs
    target_link_libraries(xlog_shared PRIVATE
        comm
        mars-boost
        libzstd_static
        "${CMAKE_SOURCE_DIR}/openssl/openssl_lib_windows/x64/libcrypto.lib"
        "${CMAKE_SOURCE_DIR}/openssl/openssl_lib_windows/x64/libssl.lib"
        ws2_32 crypt32
    )

    install(TARGETS xlog_shared
        RUNTIME DESTINATION ${SELF_LIBS_OUT}   # xlog.dll
        ARCHIVE DESTINATION ${SELF_LIBS_OUT}   # xlog.lib (import lib)
    )

    # Install linker-output PDB (requires /Zi or /DEBUG in Release)
    install(FILES "$<TARGET_PDB_FILE:xlog_shared>"
        DESTINATION ${SELF_LIBS_OUT}
        OPTIONAL
    )
endif()
