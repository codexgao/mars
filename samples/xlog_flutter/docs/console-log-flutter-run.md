# xlog Console Log 在 flutter run 下不可见的原因分析

## 问题描述

通过 `flutter run` 启动 `samples/xlog_flutter/example` 时，xlog 打印的日志无法在终端看到。但通过 Xcode 直接打开并运行 `samples/xlog_flutter/example/macos` 项目，可以在 Xcode 控制台看到完整日志输出。

---

## 原因分析

### 1. xlog Console Log 的输出实现

xlog 的 `ConsoleLog` 函数实现**因平台而异**。iOS 和 macOS 使用 `objc/objc_console.mm`，**默认通过 `os_log` 写入 macOS 统一日志系统**，而非 stdout。

**文件：** `mars/xlog/objc/objc_console.mm`

```objc
// 默认使用 os_log
static TConsoleFun sg_console_fun = TConsoleFun::kConsoleOSLog;

void ConsoleLog(const XLoggerInfo* _info, const char* _log) {
    if (kConsoleOSLog == sg_console_fun) {
        os_log_t log_t = os_log_create("", _info->tag);
        os_log_with_type(log_t, type, "[%s:%d, %s][%s", ...);
    } else if (kConsoleNSLog == sg_console_fun) {
        NSLog(@"[%s][%s]...", ...);
    } else {
        printf("%s\n", log);   // 需手动切换才会走此分支
    }
}
```

> **注意：** `mars/xlog/unix/ConsoleLog.cc`（使用 `printf()`）**不会**被 iOS/macOS 编译。
> iOS 和 macOS 的构建脚本（`CMakeLists_ios.txt` / `CMakeLists_macos.txt`）只 glob 了 `objc/*.mm`，
> `unix/` 目录完全不在编译范围内。这已通过对预编译 `libxlog.dylib` 执行 `nm` 命令确认。

`ConsoleLog` 在 `appender.cc` 中被调用：

```cpp
// mars/xlog/src/appender.cc
if (consolelog_open_)
    ConsoleLog(_info, _log);
```

console log 是否开启，由 `consolelog_open_` 字段控制，其默认值为：

```cpp
// mars/xlog/src/xlogger_appender.h
#ifdef DEBUG
    bool consolelog_open_ = true;   // Debug 构建默认开启
#else
    bool consolelog_open_ = false;  // Release 构建默认关闭
#endif
```

在 example 的 Dart 代码中，会在创建实例后显式开启：

```dart
// samples/xlog_flutter/example/lib/main.dart
_instance = XLog.open(config, level: _selectedLevel);
_instance!.consoleLogOpen = true;   // 显式启用 console log
```

---

### 2. Flutter run 的日志捕获机制

`flutter run` 通过 `DesktopLogReader` 类来捕获 macOS 应用的运行时输出。

**文件：** `packages/flutter_tools/lib/src/desktop_device.dart`（Flutter SDK 内部）

```dart
/// A log reader for desktop applications that delegates to a [Process] stdout
/// and stderr streams.
class DesktopLogReader extends DeviceLogReader {
  void initializeProcess(Process process) {
    // 仅监听应用进程的 stdout 和 stderr
    final stdoutSub = process.stdout.listen(_inputController.add);
    final stderrSub = process.stderr.listen(_inputController.add);
    // ...
  }
}
```

**关键点：**`DesktopLogReader` 只监听应用进程的 **stdout** 和 **stderr** 两个管道。这两个流是 Flutter 工具在启动子进程时创建的进程间通信管道（`pipe`），与进程本身的 `/dev/stdout` 终端设备是不同的文件描述符。

---

### 3. os_log 与 stdout 的本质区别

这是问题的核心。macOS 上 xlog 默认使用 `os_log`，而 `os_log` 的输出**完全绕过进程的 stdout/stderr**，直接写入 macOS 统一日志系统（Unified Logging System）的内核缓冲区。

| 场景 | xlog 输出目标 | flutter run 可见 | Xcode 可见 |
|------|-------------|----------------|----------|
| **flutter run 启动** | `os_log` → 系统日志缓冲区 | ❌ | ❌（无调试器附加）|
| **Xcode 运行（Debug）** | `os_log` → 系统日志缓冲区 | — | ✅（Xcode 调试器订阅系统日志）|

`DesktopLogReader` 只监听进程的 stdout/stderr pipe，而 `os_log` 根本不经过这两个流，因此 `flutter run` 无法捕获到任何 xlog 的 console log 输出。

---

### 4. 为什么 Xcode 可以看到

Xcode 以调试器（LLDB）方式运行应用，会自动订阅该进程的 **os_log 日志流**。`os_log` 正是 Apple 平台推荐的调试日志方式，Xcode 控制台对其有原生支持，因此可以看到完整输出。

---

### 5. 各输出方式对比

macOS 上 xlog 实际使用 `os_log`（默认），也可通过 `appender_set_console_fun()` 切换为 `NSLog` 或 `printf`，但三种方式均无法在 `flutter run` 终端看到：

| 输出方式 | 当前 macOS 默认 | flutter run 终端 | Xcode 控制台 | `log stream` 命令行 |
|---------|:--------------:|----------------|------------|--------------------|
| `os_log` | ✅ 是 | ❌ | ✅ | ✅ |
| `NSLog` | — | ❌ | ✅ | ✅ |
| `printf()` / stdout | — | ❌（系统日志绕过 stdout）| ✅ | ❌ |

> `printf()` 在 macOS 上虽然写入 stdout，但由于 stdout 连接 pipe 时 C 标准库切换为**全缓冲**，
> 日志会堆积在缓冲区中无法及时传递给 Flutter 工具，同样不可见。

---

## 解决方案

### 方案一：读取日志文件（推荐，零改动）

xlog 已将日志写入文件，文件路径为 `~/Documents/xlog_test/`。在另一个终端执行：

```bash
# 实时跟踪日志文件（注意 .xlog 文件为加密格式，需 xlog decode 工具解码）
ls ~/Documents/xlog_test/
```

若需要可读的纯文本内容，可暂时禁用加密（移除 `pubKey` 参数）。

### 方案二：使用 log stream 命令行工具（无需改代码，推荐）

macOS 默认已使用 `os_log`，可直接通过系统 `log` 命令在另一个终端实时查看，无需修改任何代码：

```bash
# 实时查看 Runner 进程的所有 os_log 日志
log stream --process Runner --level debug
```

### 方案三：Dart 层回调转发（彻底解决）

在 C 层增加一个回调，将日志内容转发到 Dart，由 Dart 的 `print()` 输出。`print()` 写入的是 Dart VM 的 stdout，Flutter 工具可以正常捕获。

**C 层（新增回调注册接口）：**

```c
// 注册日志回调
typedef void (*xlog_console_callback_t)(int level, const char* tag, const char* msg);
void xlog_set_console_callback(xlog_console_callback_t callback);
```

**Dart 层（注册 NativeCallable 接收日志）：**

```dart
// 使用 NativeCallable.listener 注册回调
final callback = NativeCallable<...>.listener(_onNativeLog);
bindings.xlog_set_console_callback(callback.nativeFunction);

void _onNativeLog(int level, Pointer<Char> tag, Pointer<Char> msg) {
  print('[xlog] ${tag.toDartString()}: ${msg.toDartString()}');
}
```

### 方案四：切换为 printf 并强制行缓冲

通过 `appender_set_console_fun(kConsolePrintf)` 将输出方式切换为 `printf`，再强制 stdout 行缓冲，使每次 `\n` 都立即 flush：

```objc
// 切换为 printf 模式（需在 open 之前调用）
mars::xlog::appender_set_console_fun(mars::xlog::TConsoleFun::kConsolePrintf);
```

并在 `mars/xlog/objc/objc_console.mm` 的 printf 分支中加入 `fflush`：

```cpp
printf("%s\n", log);
fflush(stdout);   // 强制立即刷新，避免全缓冲堆积
```

> 注意：此方案需重新编译 `libxlog.dylib`，且会失去 Xcode 调试器对 `os_log` 的原生支持。

---

## 相关源码位置

| 文件 | 说明 |
|------|------|
| `mars/xlog/objc/objc_console.mm:28` | macOS/iOS 的 ConsoleLog 实现（os_log / NSLog / printf 三选一）|
| `mars/xlog/objc/objc_console.mm:24` | `sg_console_fun` 默认值为 `kConsoleOSLog` |
| `mars/xlog/unix/ConsoleLog.cc` | Linux/Windows 的 ConsoleLog 实现，**不参与 iOS/macOS 编译** |
| `mars/xlog/src/appender.cc:88` | ConsoleLog 调用处 |
| `mars/xlog/src/xlogger_appender.h` | `consolelog_open_` 默认值 |
| `mars/xlog/CMakeLists_macos.txt:63` | macOS 编译 glob `objc/*.mm`，不包含 `unix/` |
| `mars/xlog/CMakeLists_ios.txt:67` | iOS 编译 glob `objc/*.mm`，不包含 `unix/` |
| `samples/xlog_flutter/lib/src/xlog.dart:192` | Dart 层 `consoleLogOpen` 属性 |
| `samples/xlog_flutter/example/lib/main.dart:87` | example 中开启 console log |
