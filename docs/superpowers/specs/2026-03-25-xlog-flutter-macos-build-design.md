# xlog Flutter macOS 构建方案设计文档

**日期：** 2026-03-25  
**作者：** CodeBuddy  
**状态：** 已批准

---

## 1. 背景

`samples/xlog_flutter` 是 mars xlog 的 Flutter FFI 插件。当前 Android 和 Windows 平台均有预编译二进制（`libxlog.so` / `xlog.dll`），通过构建脚本编译后输出到插件目录供 Flutter 直接引用。macOS 平台目前缺少对应的预编译库和构建脚本，Podspec 依赖源码编译方式（通过 C 转发器 `#include "../../src/xlog_flutter.c"`），无法独立运行。

---

## 2. 目标

1. 新建 `mars/xlog/build_macos.py`：将 xlog 编译为 macOS `libxlog.dylib`（Universal Binary：arm64 + x86_64），输出到 `samples/xlog_flutter/macos/libs/`。
2. 新建 `mars/xlog/CMakeLists_macos.txt`：xlog macOS dylib 的最小 CMake 构建定义。
3. 更新 `samples/xlog_flutter/macos/xlog_flutter.podspec`：从源码编译改为引用预编译 `libxlog.dylib`。

---

## 3. 方案选型

### 3.1 输出库格式：dylib vs xcframework

选择 **`libxlog.dylib`（Universal Binary）**，原因：

- Flutter FFI 的 Dart 侧已约定 `DynamicLibrary.open('libxlog.dylib')`，dylib 与之直接对应，无需修改 Dart 代码。
- xcframework 的核心优势是跨平台 slice 打包（macOS + iOS + Simulator），但 Flutter 插件 macOS 和 iOS 各自独立，不需要跨平台合并。
- Podspec 通过 `vendored_libraries` 引用 dylib，简单直接。

### 3.2 架构：Universal Binary (arm64 + x86_64)

- arm64：Apple Silicon（M 系列）
- x86_64：Intel Mac
- 构建方式：对两架构各跑一次 CMake，再用 `lipo` 合并

### 3.3 CMake 文件：新建 CMakeLists_macos.txt

不复用 `CMakeLists_dll.txt`（其中含大量 Windows/MSVC 特定逻辑），新建专用文件，只包含 macOS 必要的依赖和编译选项。

---

## 4. 文件变更清单

```
新建：
  mars/xlog/CMakeLists_macos.txt       — xlog macOS dylib CMake 构建定义（最小集）
  mars/xlog/build_macos.py             — macOS 构建脚本

修改：
  samples/xlog_flutter/macos/xlog_flutter.podspec  — 改用 vendored_libraries

生成（构建产物，不进 git）：
  samples/xlog_flutter/macos/libs/Release/libxlog.dylib
  samples/xlog_flutter/macos/libs/Debug/libxlog.dylib
```

---

## 5. CMakeLists_macos.txt 设计

### 5.1 依赖范围（xlog 最小集）

macOS dylib 只需静态链接以下依赖，不需要 Windows 特有的系统库：

| 依赖 | 来源 | 链接方式 |
|---|---|---|
| comm | `mars/comm/` | 静态（`add_subdirectory`） |
| mars-boost | `mars/boost/` | 静态（`add_subdirectory`） |
| libzstd_static | `mars/zstd/` | 静态（`add_subdirectory`） |
| OpenSSL | `mars/openssl/openssl_lib_osx/` | 静态（`.a`，Universal Binary x86_64+arm64） |
| z（zlib） | 系统 | 动态（`find_library`） |

**OpenSSL 特别说明**：`openssl_lib_osx/` 中的 `libcrypto.a` 和 `libssl.a` 已预编译为 Universal Binary，包含 x86_64 和 arm64 两种架构，无需按架构分别查找。CMakeLists_macos.txt 无需设置 `CMAKE_OSX_ARCHITECTURES` 对应的 OpenSSL 路径，统一使用 `openssl_lib_osx/` 即可。

### 5.2 源文件范围

```
xlog/src/*.cc / *.h          — 核心日志引擎
xlog/crypt/*.cc / *.h        — 加密（micro-ecc）
xlog/crypt/micro-ecc-master/ — ECC 实现
xlog/objc/*.mm               — Apple 平台 ObjC++ 适配
xlog/capi/*.cc / *.h         — C API 导出层（供 Flutter FFI 使用）
```

### 5.3 编译选项

```cmake
set(CMAKE_OSX_DEPLOYMENT_TARGET "10.13")  # 通过命令行传入，支持覆盖
set_target_properties(xlog_macos PROPERTIES OUTPUT_NAME "xlog")

# macOS dylib 特定配置
set_target_properties(xlog_macos PROPERTIES
    MACHO_COMPATIBILITY_VERSION 1.0.0
    MACHO_CURRENT_VERSION 1.0.0
    INSTALL_NAME_DIR "@rpath"
)

target_compile_definitions(xlog_macos PRIVATE
    XLOG_CAPI_EXPORT          # 启用 C API 导出宏
)

# Apple 编译器标志
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -stdlib=libc++")
```

**关键说明**：
- `INSTALL_NAME_DIR "@rpath"` 确保 dylib 的 install_name 为 `@rpath/libxlog.dylib`，允许 Dart FFI 通过 `DynamicLibrary.open('libxlog.dylib')` 正确加载
- Code signing：CocoaPods 集成到 Xcode 项目时，Xcode 会自动对所有库进行签名。此脚本不需要手动签名。

---

## 6. build_macos.py 设计

### 6.1 命令行参数

```
python build_macos.py --config Release         # 默认
python build_macos.py --config Debug
python build_macos.py --config Release --incremental
python build_macos.py --config Release --output-dir /path/to/output
```

| 参数 | 默认值 | 说明 |
|---|---|---|
| `--config` | `Release` | `Release` 或 `Debug` |
| `--incremental` | `False` | 跳过清理步骤 |
| `--output-dir` | `samples/xlog_flutter/macos/libs` | 输出目录 |

### 6.2 构建步骤（5步，对齐 build_windows.py）

```
[1/5] 检查环境         — 确认 macOS 平台，cmake / xcrun / clang 可用
[2/5] 生成版本文件     — gen_mars_revision_file(mars/comm)
[3/5] 配置 CMake       — 分别为 arm64 和 x86_64 生成构建目录
[4/5] 编译             — cmake --build，产出两个架构的 libxlog.dylib
[5/5] 收集输出         — lipo 合并 → 复制到 output_dir，copy_headers()
```

**环境检查细节**（步骤1）：
- 检查运行平台是 macOS（`platform.system() == 'Darwin'`）
- 检查 `cmake` 可执行（`which cmake` 或 `shutil.which`）
- 检查 Xcode 命令行工具（`xcode-select -p`）

### 6.3 CMake 调用方式

每个架构独立的构建目录：

```
build/cmake_tmp_arm64/
build/cmake_tmp_x86_64/
```

CMake 命令：
```bash
cmake <build_dir> \
  -G "Unix Makefiles" \
  -DCMAKE_BUILD_TYPE=<config> \
  -DCMAKE_OSX_ARCHITECTURES=<arch> \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=10.13 \
  -DXLOG_SOURCE_DIR=<script_dir>
```

### 6.4 输出目录结构

```
output_dir/
├── Release/
│   └── libxlog.dylib     ← Universal Binary (arm64 + x86_64)
├── Debug/
│   └── libxlog.dylib
└── include/              ← 导出的头文件（来自 XLOG_COPY_HEADER_FILES）
    ├── comm/
    └── xlog/
        └── xlog_capi.h
```

---

## 7. Podspec 更新设计

**修改前（源码编译）：**
```ruby
s.source_files = 'Classes/**/*'
s.dependency 'FlutterMacOS'
s.platform = :osx, '10.11'
```

**修改后（预编译库）：**
```ruby
s.source_files = 'Classes/**/*'
s.vendored_libraries = 'libs/Release/libxlog.dylib'
s.preserve_paths = 'libs/**/*'
s.dependency 'FlutterMacOS'
s.platform = :osx, '10.13'   # 与构建目标对齐
s.pod_target_xcconfig = {
  'DEFINES_MODULE' => 'YES',
  'OTHER_LDFLAGS' => '$(inherited) -rpath @loader_path/Frameworks'
}
```

**关键改动说明**：
- `vendored_libraries`：引用预编译的 `libs/Release/libxlog.dylib`
- `preserve_paths`：保证 libs 目录在 Pod 中被保留
- `OTHER_LDFLAGS` 添加 `-rpath @loader_path/Frameworks`：确保动态链接器能正确找到 dylib（CocoaPods 将库放在 app bundle 的 Frameworks 目录中）
- Platform 从 `10.11` 升级到 `10.13`，与构建配置对齐

---

## 8. 不在本次范围内

- iOS 平台的预编译库改造（iOS 现有方案能正常工作）
- Linux 平台改造
- Dart FFI 绑定代码修改（`xlog.dart` 中的 `libxlog.dylib` 加载逻辑已正确）
- Code signing（Xcode 集成时会自动处理）

---

## 9. 附录：OpenSSL 预编译特性说明

`mars/openssl/openssl_lib_osx/` 中的 OpenSSL 库已预编译为 Universal Binary，包含 x86_64 和 arm64 两个 slice。这种设计的优势：

- 无需对两个架构分别 `find_library`
- CMake 构建两个架构的 dylib 时，都可以直接链接同一个 Universal OpenSSL `.a` 文件
- `lipo` 合并时无需担心 OpenSSL 不匹配

如果未来 OpenSSL 需要更新，维护者可在 `openssl_lib_osx/` 目录中替换预编译的 `.a` 文件，无需修改此构建脚本。

---

## 10. 验证方式

构建脚本完成后，通过以下步骤验证：

1. 运行 `python mars/xlog/build_macos.py --config Release`
2. 确认 `samples/xlog_flutter/macos/libs/Release/libxlog.dylib` 存在
3. 验证 Universal Binary 和 install_name：
   ```bash
   lipo -info samples/xlog_flutter/macos/libs/Release/libxlog.dylib
   # 预期输出: Architectures in the fat file: ... are: x86_64 arm64
   
   otool -D samples/xlog_flutter/macos/libs/Release/libxlog.dylib
   # 预期输出: /path/to/lib contains:
   #           @rpath/libxlog.dylib
   ```
4. 验证符号导出：
   ```bash
   nm samples/xlog_flutter/macos/libs/Release/libxlog.dylib | grep xlog_new_instance
   # 预期输出: 包含 xlog_new_instance 等 C API 函数
   ```
5. 在 `samples/xlog_flutter/example/` 中运行 `flutter run -d macos`
6. 确认应用启动成功，且日志正常写入（无 dylib 加载错误）
