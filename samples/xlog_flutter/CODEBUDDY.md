# CODEBUDDY.md

This file provides guidance to CodeBuddy Code when working with code in this repository.

## 项目概述

`xlog_flutter` 是一个 Flutter FFI 插件，对腾讯 Mars XLog 高性能日志库进行封装，支持 Android、iOS、macOS、Windows、Linux 平台。采用**纯 FFI 方式**（无 MethodChannel），直接调用原生函数。

## 项目结构

```
xlog_flutter/
├── src/                           # 跨平台 C++ FFI 包装层
│   ├── xlog_flutter.h             # C FFI 接口声明（8个函数）
│   └── xlog_flutter.cpp           # C 包装实现，桥接 mars::xlog::appender_*
├── lib/                           # Dart 层
│   ├── xlog_flutter.dart          # 高级 Dart API
│   └── xlog_flutter_bindings_generated.dart  # 自动生成的 FFI 绑定（勿手动修改）
├── include/                       # 从 mars/xlog 同步的头文件
├── android/                       # Android NDK + CMake 构建
│   ├── CMakeLists.txt
│   └── libs/                      # 预编译 libmarsxlog.so 存放目录
├── ios/                           # iOS CocoaPods 构建
│   ├── xlog_flutter.podspec
│   └── libs/                      # 预编译 MarsXlog.xcframework 存放目录
├── macos/                         # macOS CocoaPods 构建（与 iOS 结构类似）
├── windows/                       # Windows CMake 构建
│   ├── CMakeLists.txt
│   ├── src/sys/                   # POSIX 兼容垫片（gettimeofday）
│   └── libs/                      # 预编译 xlog.dll/xlog.lib 存放目录
├── linux/                         # Linux CMake 构建
│   └── libs/                      # 预编译 libxlog.a 存放目录
├── example/                       # Flutter 示例应用
├── ffigen.yaml                    # FFI 代码生成配置
└── sync_headers.py                # 从 mars/xlog 同步头文件的脚本
```

## 关键依赖前提

**插件本身不构建 Mars 原生库**，必须先将预编译库放到对应目录：

| 平台    | 预编译库路径                                         |
|---------|------------------------------------------------------|
| Android | `android/libs/{Debug,Release}/{arch}/libmarsxlog.so` |
| iOS     | `ios/libs/MarsXlog.xcframework`                      |
| macOS   | `macos/libs/MarsXlog.xcframework`                    |
| Windows | `windows/libs/x64/{Debug,Release}/xlog.{lib,dll}`   |
| Linux   | `linux/libs/x64/libxlog.a`                          |

## 构建 Mars 原生库（从 mars/ 根目录执行）

```bash
# Android
python build_android.py

# iOS（输出 MarsXlog.xcframework）
python build_ios.py --xlog

# macOS
python build_osx.py --xlog

# Windows（xlog 仅）
python build_windows.py --xlog --config Release

# Linux
cd cmake_build && cmake ../.. && cmake --build . --target xlog
```

## 开发命令

### Flutter 常规命令

```bash
# 获取依赖
flutter pub get

# 运行示例应用
cd example && flutter run

# 运行 Flutter 测试
flutter test

# 代码分析（lint）
flutter analyze

# 格式化 Dart 代码
dart format lib/
```

### 重新生成 FFI 绑定

修改 `src/xlog_flutter.h` 后，必须重新生成绑定：

```bash
dart run ffigen --config ffigen.yaml
```

生成结果写入 `lib/xlog_flutter_bindings_generated.dart`，勿手动修改此文件。

### 同步 Mars 头文件

当 Mars xlog 头文件更新后，使用以下命令同步到插件 `include/` 目录：

```bash
# 实际同步
python sync_headers.py

# 仅检查差异，不执行修改
python sync_headers.py --check
```

## 架构说明

### FFI 调用链

```
Dart (xlog_flutter.dart)
    ↓ FFI 直接调用
C 接口 (src/xlog_flutter.h / .cpp)
    ↓ 调用 C++ API
mars::xlog::appender_* 函数（预编译库）
```

### 核心 Dart API（`lib/xlog_flutter.dart`）

- `XLogConfig`：配置类，包含 `logDir`、`namePrefix`、`level`、`mode`（async/sync）、`compressMode`（zlib/zstd）、`pubKey`（ECC 加密公钥）、`cacheDir`、`cacheDays`
- `XLog.open(config)`：初始化日志器
- `XLog.close()`：关闭日志器
- `XLog.flush(sync: bool)`：刷新缓冲区
- `XLog.write(level, tag, message)`：写日志（通常通过 verbose/debug/info/warn/error/fatal 调用）
- `XLog.setConsoleLog(bool)`、`setLevel(LogLevel)`、`setMaxFileSize(int)`、`setMaxAliveDuration(int)`

### C FFI 层（`src/xlog_flutter.cpp`）

- 将 Dart 传入的 UTF-8 C 字符串转换为 Mars C++ API 所需格式
- 提取进程 ID、线程 ID、当前时间戳，传给 `xlogger_Write`
- 封装 `appender_open`、`appender_close`、`appender_flush`、`appender_setlevel` 等

### 内存安全规范

Dart 侧所有字符串跨 FFI 传递时，必须：

```dart
final ptr = str.toNativeUtf8();
try {
  nativeFunction(ptr);
} finally {
  malloc.free(ptr);
}
```

## 平台集成要点

- **iOS/macOS**: 最小平台版本分别为 iOS 12.0 / macOS 10.14；原生代码极少（仅 podspec + 一行 `#include`）
- **Android**: minSdk=21，支持 arm64-v8a 和 armeabi-v7a
- **Windows**: 包含 `gettimeofday` POSIX 兼容垫片（`windows/src/sys/`）；需将 `xlog.dll` 一起分发

## 多进程安全

- 多进程场景下，**每个进程必须使用独立的日志目录**，否则会触发 SIGBUS
- 建议在 Android 上配置单独的 `cacheDir`
