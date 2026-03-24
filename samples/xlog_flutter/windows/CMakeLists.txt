# The Flutter tooling requires that developers have a version of Visual Studio
# installed that includes CMake 3.14 or later. You should not increase this
# version, as doing so will cause the plugin to fail to compile for some
# customers of the plugin.
cmake_minimum_required(VERSION 3.14)

project(xlog_flutter_plugin LANGUAGES C CXX)

# Resolve real path — Flutter uses symlinks for plugin references.
get_filename_component(PLUGIN_DIR "${CMAKE_CURRENT_SOURCE_DIR}" REALPATH)

# Prebuilt binaries shipped with the plugin (windows/libs/).
set(XLOG_LIBS_DIR "${PLUGIN_DIR}/libs")

# Imported shared library (prebuilt, not compiled here).
# This makes the target available for native consumers in the host app
# who want to link against xlog and call xlog_capi.h functions directly.
add_library(xlog_flutter SHARED IMPORTED GLOBAL)
set_target_properties(xlog_flutter PROPERTIES
  IMPORTED_IMPLIB "${XLOG_LIBS_DIR}/xlog.lib"
  IMPORTED_LOCATION "${XLOG_LIBS_DIR}/xlog.dll"
)

# Expose headers so native consumers can:
#   #include "xlog/xlog_capi.h"
target_include_directories(xlog_flutter INTERFACE
  "${PLUGIN_DIR}/../include"
)

# Bundle the DLL (and optionally PDB) into the Flutter application.
set(xlog_flutter_bundled_libraries
  "${XLOG_LIBS_DIR}/xlog.dll"
  PARENT_SCOPE
)
