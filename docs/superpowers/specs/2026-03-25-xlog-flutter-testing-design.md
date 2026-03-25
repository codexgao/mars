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

- 使用 `package:integration_test/integration_test.dart`
- 每个测试前创建临时目录作为 `logdir`，测试后清理
- 统一 `nameprefix` 命名规范，避免实例名冲突
- `tearDown` 确保每个测试后调用 `XLog.release()` 清理实例

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
| 未初始化时调用 `get()` | 返回 null 或抛出异常 |
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
| 写入后 `logPath` 非空 | 路径字符串有效 |
| `flush(sync: true)` 后文件 size > 0 | 数据已落盘 |
| `flush(sync: false)` | 不崩溃 |
| `flushAll()` | 不崩溃 |
| `XLogConfig.compressMode = zlib` | 文件正常生成 |
| `XLogConfig.compressMode = zstd` | 文件正常生成 |
| `XLogConfig.pubKey` 加密开启 | 文件正常生成 |
| `XLogConfig.cachedir` 指定独立缓存目录 | 不崩溃 |
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
| 同时开两个实例写入 | 两个实例各自 `logPath` 不同 |
| 两实例互不干扰 | release 一个，另一个仍 `isValid` |
| `flushAll()` 刷新所有实例 | 不崩溃 |
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

**文件位置：** `example/android/app/src/androidTest/.../XlogNativeTest.kt`

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

测试代码结构与 Android JNA 类似，直接调用 C API，覆盖相同用例集。代码写好后标注 `// TODO: verify on target platform`，不纳入当前验收范围。

---

## 6. 依赖变更

`example/pubspec.yaml` 需添加：
```yaml
dev_dependencies:
  integration_test:
    sdk: flutter
```

---

## 7. 验收标准

- [ ] Flutter 集成测试在 macOS、iOS Simulator、Android Emulator 上全部通过
- [ ] macOS XCTest 全部通过
- [ ] iOS XCTest 全部通过
- [ ] Android JUnit Instrumented Test 全部通过
- [ ] Windows / Linux 测试代码已写好（暂不要求通过）
- [ ] 每个测试用例在 tearDown 中清理临时文件和实例
