# xlog_flutter 完整测试方案设计

**日期：** 2026-03-25  
**范围：** `samples/xlog_flutter`  
**状态：** 已批准

---

## 1. 背景

`xlog_flutter` 是一个 Flutter FFI 插件，封装了 Mars xlog 的 C API，提供跨平台（Android、iOS、macOS、Windows、Linux）的高性能日志功能。插件同时支持：

- **Dart 层调用**：通过 FFI 直接调用 C API
- **原生层调用**：iOS/macOS 通过 ObjC 包装层（`darwin/Classes/`），Android 通过 JNA 绑定

当前已有测试文件极少，缺乏系统性覆盖。本设计目标是为插件添加完整测试，涵盖集成测试和各平台原生测试。

---

## 2. 测试策略

### 2.1 不包含单元测试

插件核心功能依赖 FFI 调用原生库，在纯 Dart VM 环境下无法加载原生库，单元测试价值有限，故不添加。

### 2.2 两层测试架构

| 层次 | 框架 | 运行环境 | 覆盖内容 |
|------|------|----------|----------|
| Flutter 集成测试 | `integration_test` | 真实设备 / 模拟器 | Dart 公开 API 全覆盖，跨平台行为 |
| 原生平台测试 | XCTest / JUnit | Xcode / ADB | ObjC 包装层 / JNA 绑定 |

### 2.3 平台优先级

- **优先保证通过：** Android、iOS、macOS
- **测试代码编写但暂缓验证：** Windows、Linux

---

## 3. 目录结构

```
xlog_flutter/
├── example/
│   ├── integration_test/
│   │   ├── xlog_open_test.dart          # 实例生命周期
│   │   ├── xlog_write_test.dart         # 写日志
│   │   ├── xlog_level_test.dart         # 级别控制
│   │   ├── xlog_control_test.dart       # 控制方法
│   │   ├── xlog_multi_instance_test.dart # 多实例
│   │   └── xlog_all_test.dart           # 入口，聚合所有测试
│   ├── android/app/src/androidTest/
│   │   └── XlogNativeTest.kt            # Android JUnit 原生测试（扩展现有）
│   ├── ios/RunnerTests/
│   │   └── XlogNativeTests.swift        # iOS XCTest（扩展现有）
│   └── macos/RunnerTests/
│       └── XlogNativeTests.swift        # macOS XCTest（扩展现有）
```

---

## 4. Flutter 集成测试详细设计

### 4.1 测试基础设施

#### 4.1.1 共享测试工具类

创建 `example/integration_test/test_utils.dart`，提供通用 setup/teardown 和临时目录管理：

```dart
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class XlogTestUtils {
  static late Directory tempLogDir;
  
  static Future<void> setUp() async {
    tempLogDir = await getTemporaryDirectory();
  }
  
  static Future<void> tearDown(String nameprefix) async {
    XLog.release(nameprefix);
    if (tempLogDir.existsSync()) {
      await tempLogDir.delete(recursive: true);
    }
  }
}
```

#### 4.1.2 测试编写规范

- 使用 `package:integration_test/integration_test.dart`
- 每个测试文件在 `setUpAll()` 初始化临时目录，`tearDown()` 中调用 `XlogTestUtils.tearDown()`
- 统一 `nameprefix` 命名规范：`test_instance_${test_name}_${timestamp}`，避免实例名冲突
- 每个测试用例必须独立 `open()` 一个实例，测试结束前 `release()`

### 4.2 `xlog_open_test.dart` — 实例生命周期

| 用例 | 验证点 |
|------|--------|
| `open()` 返回有效实例 | `instance.isValid == true` |
| `open()` 后 `has()` 返回 true | `XLog.has(name) == true` |
| `get()` 取回同一实例 | `get().handle == open().handle` |
| 重复 `open()` 同名实例 | 验证返回已有实例或抛出异常（记录当前行为） |
| `release()` 后 `has()` 返回 false | `XLog.has(name) == false` |
| `destroy()` 通过 handle 销毁 | 实例随后不可用 |
| `release()` 不存在的名字 | 不崩溃 |
| 未初始化时调用 `get()` | 返回 `handle == 0` 的无效实例（`isValid == false`） |
| `isInitialized` 在 `initialize()` 后为 true | 标志位正确 |

### 4.3 `xlog_write_test.dart` — 写日志

| 用例 | 验证点 |
|------|--------|
| `verbose()` 写入一条 | 不崩溃，flush 后文件存在 |
| `debug()` 写入一条 | 同上 |
| `info()` 写入一条 | 同上 |
| `warn()` 写入一条 | 同上 |
| `error()` 写入一条 | 同上 |
| `fatal()` 写入一条 | 同上 |
| `write()` 指定各级别 | 功能等价于对应快捷方法 |
| 带 `filename` 参数写入 | 不崩溃 |
| 带 `funcname` 参数写入 | 不崩溃 |
| 带 `line` 参数写入 | 不崩溃 |
| 写入后 `logPath` 非空 | 路径包含 nameprefix，文件系统中文件存在 |
| `flush(sync: true)` 后文件 size > 0 | 文件 size >= 50 字节（含日志元数据） |
| `flush(sync: false)` | 不崩溃 |
| `flushAll()` | 不崩溃 |
| `XLogConfig.compressMode = zlib` | 文件生成，检查 zlib magic bytes (0x78, 0x9C) |
| `XLogConfig.compressMode = zstd` | 文件生成，检查 zstd magic bytes (0x28, 0xB5, 0x2F, 0xFD) |
| `XLogConfig.pubKey` 加密开启 | 文件加密，size > 100，文件头不为可读 ASCII 文本 |
| `XLogConfig.cachedir` 指定独立缓存目录 | 不崩溃，缓存生成在指定目录 |
| `XLogConfig.cacheDays` 设置 | 不崩溃 |

### 4.4 `xlog_level_test.dart` — 级别控制

| 用例 | 验证点 |
|------|--------|
| 设置 `level = debug`，`isEnabledFor(verbose)` | 返回 false |
| 设置 `level = debug`，`isEnabledFor(debug)` | 返回 true |
| 设置 `level = debug`，`isEnabledFor(info)` | 返回 true |
| `level` getter 与 setter 一致 | `get == set` |
| 设置 `level = all` | 不崩溃，`isEnabledFor(verbose) == true` |
| 设置 `level = none` | 不崩溃，`isEnabledFor(fatal) == false` |
| 逐一设置所有枚举值 | 不崩溃 |

### 4.5 `xlog_control_test.dart` — 控制方法

| 用例 | 验证点 |
|------|--------|
| `appenderMode = sync_` | 不崩溃 |
| `appenderMode = async_` | 不崩溃 |
| `consoleLogOpen = true` | 不崩溃 |
| `consoleLogOpen = false` | 不崩溃 |
| `flush(sync: true)` | 不崩溃 |
| `flush(sync: false)` | 不崩溃 |
| `logPath` 在 open 后非空 | 路径包含 nameprefix |

### 4.6 `xlog_multi_instance_test.dart` — 多实例

| 用例 | 验证点 |
|------|--------|
| 同时开两个实例写入 | 两个实例各自 `logPath` 完全不同，each logs 单独文件集 |
| 两实例级别独立 | 修改 instance1 的 level 不影响 instance2 的 level |
| 两实例 appender 独立 | 设置 instance1 为 sync，instance2 为 async，各自表现正确 |
| 两实例互不干扰 | release 一个，另一个仍 `isValid == true` 且日志写入正常 |
| `flushAll()` 刷新所有实例 | 不崩溃，两个实例日志都被 flush |
| 分别 `release()` 各实例 | 均释放后 `has()` 均返回 false |

---

## 5. 原生平台测试详细设计

### 5.1 iOS / macOS XCTest

**文件位置：**
- iOS：`example/ios/RunnerTests/XlogNativeTests.swift`
- macOS：`example/macos/RunnerTests/XlogNativeTests.swift`

**测试通过 ObjC 包装层调用（`darwin/Classes/`）：**

| 用例 | 验证点 |
|------|--------|
| `XLogManager` 创建实例 | 返回非 nil `XLogInstance` |
| `XLogManager.has()` | 返回 true |
| `XLogManager.get()` | 返回同一实例 |
| `XLogManager.release()` | 释放后 `has()` 返回 false |
| `XLogInstance` 写入 verbose/debug/info/warn/error/fatal | 不崩溃 |
| `XLogInstance.level` get/set | 值一致 |
| `XLogInstance.flush()` | 不崩溃 |
| `XLogInstance.logPath` | 路径非空 |
| `XLogConfig` 各字段赋值传递 | 字段值正确 |

**运行命令：**
```bash
# macOS
xcodebuild test \
  -workspace example/macos/Runner.xcworkspace \
  -scheme Runner \
  -destination 'platform=macOS'

# iOS Simulator
xcodebuild test \
  -workspace example/ios/Runner.xcworkspace \
  -scheme Runner \
  -destination 'platform=iOS Simulator,name=iPhone 15'
```

### 5.2 Android JUnit Instrumented Test

**文件位置：** `example/android/app/src/androidTest/java/com/codexgao/xlog_flutter_example/XlogNativeTest.kt`  
（扩展或替代现有 `XlogNativeInstrumentedTest.kt`）

**测试通过 JNA 直接调用 C API（与 Dart FFI 同层）：**

| 用例 | 验证点 |
|------|--------|
| `xlog_new_instance()` | 返回非零 handle |
| `xlog_has_instance()` | 返回 true |
| `xlog_get_instance()` | 返回非零 handle |
| `xlog_write()` 各级别 | 不崩溃 |
| `xlog_get_level()` / `xlog_set_level()` | get == set |
| `xlog_set_appender_mode()` sync/async | 不崩溃 |
| `xlog_set_console_log_open()` true/false | 不崩溃 |
| `xlog_flush()` sync/async | 不崩溃 |
| `xlog_flush_all()` | 不崩溃 |
| `xlog_get_log_path()` | 路径非空 |
| `xlog_release_instance()` | 随后 `has()` 返回 false |
| `xlog_destroy_instance()` | 不崩溃 |

**运行命令：**
```bash
cd example/android
./gradlew connectedAndroidTest
```

### 5.3 Windows / Linux（暂缓验证）

**测试框架：** C API 直接调用（结构同 Android JNA）

**文件位置：**
- Windows：`example/windows/runner/xlog_native_test.cpp`
- Linux：`example/linux/runner/xlog_native_test.cpp`

**用例表：** 与 Section 5.2 相同，用 C++ 或纯 C 调用 xlog C API，覆盖所有函数。

**状态标记：** 代码编写完毕后标注 `// TODO: verify on target platform`，当前不在验收范围内。

---

### 5.4 平台特定设置

#### macOS
- dylib 必须带有有效代码签名或关闭 SIP（`xcode-select --switch`）
- 临时目录需要写权限（通常 `/tmp`、`~/Library/Caches`）

#### iOS
- FFI 通过 `DynamicLibrary.process()` 加载 `xlog.framework` 需要 bitcode 兼容（iOS 14.0+）
- 临时目录受 App Sandbox 限制，应使用 `getApplicationDocumentsDirectory()` 而非系统 `/tmp`

#### Android
- 验证 `build.gradle` 中 `abiFilters` 包含测试架构（通常 `arm64-v8a` 优先）
- NDK 架构：测试运行的 Emulator 必须与 `.so` 库架构匹配（如 arm64-v8a Emulator 不能用 x86 库）

#### Linux
- `/tmp` 可能被定期清理，应使用 `$XDG_RUNTIME_DIR` 或显式创建持久化临时目录
- 权限：`libxlog.so` 必须在 `LD_LIBRARY_PATH` 或 runner 应用所在目录

---

## 6. 依赖变更

### 6.1 `example/pubspec.yaml`

```yaml
dev_dependencies:
  integration_test:
    sdk: flutter
  flutter_test:
    sdk: flutter
  path_provider: ^2.1.0          # 用于 getTemporaryDirectory()
```

### 6.2 iOS Podspec（验证配置）

确保 `example/ios/Podfile` 和 `xlog_flutter.podspec` 中使用正确的 rpath 配置：

```ruby
# ✓ 正确
pod_target_xcconfig = {
  'LD_RUNPATH_SEARCH_PATHS' => '@loader_path/Frameworks'
}

# ✗ 错误（不使用）
pod_target_xcconfig = {
  'OTHER_LDFLAGS' => '-rpath @loader_path/Frameworks'
}
```

### 6.3 Android Build Setup

验证 `example/android/build.gradle` 和 `app/build.gradle`：
- NDK 已安装（`~/Library/Android/sdk/ndk/`）
- `minSdkVersion >= 21`（xlog_flutter 要求）
- `abiFilters` 包含 ARM64（推荐：`arm64-v8a`）

---

## 7. 验收标准

- [ ] Flutter 集成测试在 macOS、iOS Simulator、Android Emulator 上全部通过（总耗时 < 5 min）
- [ ] macOS XCTest 全部通过（< 1 min）
- [ ] iOS XCTest 全部通过（< 2 min）
- [ ] Android JUnit Instrumented Test 全部通过（< 2 min）
- [ ] 测试代码覆盖 Dart/ObjC/JNA/C API 所有公开方法
- [ ] 所有测试日志保存到 `test_output/` 目录：
  - Flutter 集成测试 JSON 报告（`flutter test --reporter=json`）
  - XCTest 结果（`xcresult`）
  - Android Test XML 报告（JUnit XML）
- [ ] 每个测试用例在 `tearDown` 中正确清理临时文件和实例
- [ ] Windows / Linux 测试代码已编写（标注 TODO，暂不要求通过）

---

## 8. 测试运行指南

### 8.1 Flutter 集成测试

```bash
cd example

# macOS
flutter test integration_test/ -d macos

# iOS Simulator（需先启动模拟器）
open -a Simulator
flutter test integration_test/ -d ios

# Android Emulator（需先启动模拟器）
cd ../..
$ANDROID_HOME/emulator/emulator -avd Pixel_4_API_30 &
cd example
flutter test integration_test/ -d android
```

### 8.2 macOS XCTest

```bash
cd example
flutter pub get

xcodebuild test \
  -workspace macos/Runner.xcworkspace \
  -scheme Runner \
  -destination 'platform=macOS' \
  -resultBundlePath macos/test_result.xcresult
```

### 8.3 iOS XCTest

```bash
cd example
flutter pub get

# 确保 CocoaPods 依赖已安装
cd ios
pod install --repo-update
cd ../..

# 列出可用模拟器
xcrun simctl list devices

xcodebuild test \
  -workspace example/ios/Runner.xcworkspace \
  -scheme Runner \
  -destination 'platform=iOS Simulator,name=iPhone 15,OS=18.2' \
  -resultBundlePath example/ios/test_result.xcresult
```

### 8.4 Android JUnit Instrumented Test

```bash
cd example/android

# 启动 emulator（需 Android SDK 已安装）
$ANDROID_HOME/emulator/emulator -avd Pixel_4_API_30 &

# 运行测试
./gradlew connectedAndroidTest -x lint

# 测试报告位置
# build/outputs/androidTest-results/connected/
```
