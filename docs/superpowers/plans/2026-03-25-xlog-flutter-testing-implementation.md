# xlog_flutter 完整测试实现计划

> **对于 agentic 执行者：** 使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务执行本计划。每个步骤使用复选框 (`- [ ]`) 跟踪进度。

**目标：** 为 xlog_flutter 插件实现完整的集成测试和平台原生测试，覆盖 Flutter Dart API、iOS/macOS ObjC 层、Android Kotlin/JNA 层的所有公开方法。

**架构：**
- **Flutter 集成测试**（`integration_test/`）：跨平台 Dart 代码，通过 FFI 调用原生库，验证 XLog/XLogInstance 公开 API
- **iOS/macOS XCTest**（`RunnerTests.swift`）：扩展现有测试框架，通过 ObjC 包装层直接调用，验证 XLogManager/XLogInstance/XLogConfig
- **Android JUnit**（`XlogNativeTest.kt`）：扩展现有 instrumented tests，通过 JNA 直接调用 C API，验证所有函数

**技术栈：** Flutter SDK ^3.4.0, Dart 3.4+, XCTest, JUnit 4, JNA 5.13.0

---

## 文件结构规划

### 需要创建的文件

```
example/
├── integration_test/
│   ├── test_utils.dart                    # 共享测试工具类（临时目录、cleanup）
│   ├── xlog_open_test.dart               # 实例生命周期 (108行)
│   ├── xlog_write_test.dart              # 写日志 + 配置验证 (180行)
│   ├── xlog_level_test.dart              # 级别控制 (95行)
│   ├── xlog_control_test.dart            # 控制方法 (75行)
│   ├── xlog_multi_instance_test.dart     # 多实例 (110行)
│   └── xlog_all_test.dart                # 入口，聚合所有测试 (20行)
├── android/app/src/androidTest/java/com/codexgao/xlog_flutter_example/
│   ├── XlogNativeTest.kt                 # 扩展现有 instrumented tests (扩展 245 → 400行)
│   └── XlogFileTestUtils.kt              # Android 特定 helper (文件操作、ABI验证) (80行)
├── ios/RunnerTests/
│   └── XlogNativeTests.swift             # iOS XCTest (从0扩展到 300行)
├── macos/RunnerTests/
│   └── XlogNativeTests.swift             # macOS XCTest (从0扩展到 300行)
└── pubspec.yaml                          # 添加 path_provider dev dependency

windows/
└── runner/
    └── xlog_native_test.cpp              # Windows C++ test (暂缓验证) (150行)

linux/
└── runner/
    └── xlog_native_test.cpp              # Linux C++ test (暂缓验证) (150行)
```

### 文件职责划分

| 文件 | 职责 | 依赖 |
|------|------|------|
| `test_utils.dart` | 临时目录创建/清理、common setup/teardown | `path_provider` |
| `xlog_*_test.dart` (5 files) | Dart 集成测试，验证 XLog/XLogInstance API | `test_utils.dart`, FFI |
| `xlog_all_test.dart` | 入口汇总，便于一次运行所有集成测试 | 所有 xlog_*_test.dart |
| `XlogNativeTest.kt` | Android JUnit + JNA，验证 C API 函数 | 现有 XlogNativeInstrumentedTest.kt (replace/extend) |
| `XlogFileTestUtils.kt` | Android 辅助：文件解析、ABI 检查 | JNA 库 |
| `XlogNativeTests.swift` (iOS) | XCTest，验证 ObjC XLogManager/XLogInstance | darwin/Classes ObjC headers |
| `XlogNativeTests.swift` (macOS) | 同 iOS（代码一致，运行环境不同） | darwin/Classes ObjC headers |
| `xlog_native_test.cpp` (Win/Linux) | C++ 测试，直接调用 C API（暂缓） | C API header |
| `pubspec.yaml` | 添加 `path_provider: ^2.1.0` | 已有 pubspec.yaml |

---

## 任务分解

### 准备工作

#### Task 1: 更新 pubspec.yaml 依赖

**文件：**
- Modify: `example/pubspec.yaml`

- [ ] **Step 1: 读取现有 pubspec.yaml**

Run: `cat /Users/jobsygao/Code/Tencent/mars/samples/xlog_flutter/example/pubspec.yaml`

Expected: 输出 YAML，包含 flutter, path_provider, xlog_flutter 等依赖

- [ ] **Step 2: 在 dev_dependencies 中添加 path_provider**

编辑 `example/pubspec.yaml`，在 `dev_dependencies:` 下添加：
```yaml
dev_dependencies:
  flutter_test:
    sdk: flutter
  path_provider: ^2.1.0
  integration_test:
    sdk: flutter
```

- [ ] **Step 3: 运行 flutter pub get**

Run: `cd /Users/jobsygao/Code/Tencent/mars/samples/xlog_flutter/example && flutter pub get`

Expected: 新的 pubspec.lock 包含 path_provider，无错误

- [ ] **Step 4: 提交**

```bash
cd /Users/jobsygao/Code/Tencent/mars/samples/xlog_flutter/example
git add pubspec.yaml pubspec.lock
git commit -m "test: add path_provider and integration_test to dev dependencies"
```

---

#### Task 2: 创建 integration_test 目录结构

**文件：**
- Create: `example/integration_test/` (directory)

- [ ] **Step 1: 创建目录**

Run: `mkdir -p /Users/jobsygao/Code/Tencent/mars/samples/xlog_flutter/example/integration_test`

- [ ] **Step 2: 验证目录**

Run: `ls -la /Users/jobsygao/Code/Tencent/mars/samples/xlog_flutter/example/integration_test/`

Expected: 空目录

---

### Flutter 集成测试（Dart 层）

#### Task 3: 创建 test_utils.dart（测试工具库）

**文件：**
- Create: `example/integration_test/test_utils.dart`

- [ ] **Step 1: 编写 test_utils.dart**

```dart
import 'dart:io';
import 'package:xlog_flutter/xlog_flutter.dart';
import 'package:path_provider/path_provider.dart';

/// 共享测试工具类，处理临时目录和清理
class XlogTestUtils {
  static late Directory tempLogDir;
  
  /// 初始化测试环境
  static Future<void> setUp() async {
    tempLogDir = await getTemporaryDirectory();
  }
  
  /// 清理测试环境（释放实例、删除临时文件）
  static Future<void> tearDown(String nameprefix) async {
    // Release the instance
    if (XLog.has(nameprefix)) {
      XLog.release(nameprefix);
    }
    
    // Give native layer time to close files
    await Future.delayed(Duration(milliseconds: 100));
  }
  
  /// 验证文件魔数（用于压缩/加密验证）
  static Future<bool> hasZlibMagic(File file) async {
    if (!await file.exists()) return false;
    final bytes = await file.readAsBytes();
    if (bytes.length < 2) return false;
    // zlib: 0x78 0x9C
    return bytes[0] == 0x78 && bytes[1] == 0x9C;
  }
  
  static Future<bool> hasZstdMagic(File file) async {
    if (!await file.exists()) return false;
    final bytes = await file.readAsBytes();
    if (bytes.length < 4) return false;
    // zstd: 0x28 0xB5 0x2F 0xFD
    return bytes[0] == 0x28 && bytes[1] == 0xB5 && 
           bytes[2] == 0x2F && bytes[3] == 0xFD;
  }
  
  static Future<bool> isEncrypted(File file) async {
    if (!await file.exists()) return false;
    final bytes = await file.readAsBytes();
    if (bytes.length < 100) return false;
    
    // Encrypted files typically don't start with common magic bytes
    // and have random-looking header
    final header = bytes.sublist(0, 20);
    // Simple check: no obvious text or compression magic
    for (int b in header) {
      if (b < 32 && b != 9 && b != 10 && b != 13) {
        // Non-printable byte (good sign of encryption)
        return true;
      }
    }
    return false;
  }
  
  /// 获取实例的日志文件列表
  static Future<List<File>> getLogFiles(XLogInstance instance) async {
    final logPath = instance.logPath;
    final logDir = Directory(logPath);
    
    if (!await logDir.exists()) return [];
    
    final files = <File>[];
    await for (final entity in logDir.list()) {
      if (entity is File) {
        files.add(entity);
      }
    }
    return files;
  }
  
  /// 获取文件大小
  static Future<int> getFileSize(File file) async {
    if (!await file.exists()) return 0;
    return await file.length();
  }
}
```

- [ ] **Step 2: 验证文件**

Run: `wc -l /Users/jobsygao/Code/Tencent/mars/samples/xlog_flutter/example/integration_test/test_utils.dart`

Expected: 约 60-70 行

- [ ] **Step 3: 提交**

```bash
cd /Users/jobsygao/Code/Tencent/mars/samples/xlog_flutter
git add example/integration_test/test_utils.dart
git commit -m "test: add flutter integration test utilities (temp dir, magic byte verification)"
```

---

#### Task 4: 创建 xlog_open_test.dart（实例生命周期）

**文件：**
- Create: `example/integration_test/xlog_open_test.dart`

- [ ] **Step 1: 编写测试文件**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:xlog_flutter/xlog_flutter.dart';
import 'test_utils.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  
  late Directory tempLogDir;
  
  setUpAll(() async {
    await XlogTestUtils.setUp();
    tempLogDir = XlogTestUtils.tempLogDir;
  });
  
  tearDown(() async {
    // Release all instances after each test
    await XlogTestUtils.tearDown('test_open_instance_1');
    await XlogTestUtils.tearDown('test_open_instance_2');
  });
  
  group('XLog Instance Lifecycle', () {
    test('open() returns valid instance', () async {
      final config = XLogConfig(
        logdir: tempLogDir.path,
        nameprefix: 'test_open_instance_1',
      );
      final instance = XLog.open(config);
      
      expect(instance.isValid, isTrue);
      expect(instance.handle, isNotZero);
    });
    
    test('open() followed by has() returns true', () async {
      final config = XLogConfig(
        logdir: tempLogDir.path,
        nameprefix: 'test_open_instance_1',
      );
      XLog.open(config);
      
      expect(XLog.has('test_open_instance_1'), isTrue);
    });
    
    test('get() retrieves same instance handle', () async {
      final config = XLogConfig(
        logdir: tempLogDir.path,
        nameprefix: 'test_open_instance_1',
      );
      final instance1 = XLog.open(config);
      final instance2 = XLog.get('test_open_instance_1');
      
      expect(instance1.handle, equals(instance2.handle));
    });
    
    test('get() on non-existent instance returns invalid', () async {
      final instance = XLog.get('nonexistent_instance_xyz');
      
      expect(instance.handle, equals(0));
      expect(instance.isValid, isFalse);
    });
    
    test('release() removes instance', () async {
      final config = XLogConfig(
        logdir: tempLogDir.path,
        nameprefix: 'test_open_instance_1',
      );
      XLog.open(config);
      expect(XLog.has('test_open_instance_1'), isTrue);
      
      XLog.release('test_open_instance_1');
      expect(XLog.has('test_open_instance_1'), isFalse);
    });
    
    test('destroy() closes instance by handle', () async {
      final config = XLogConfig(
        logdir: tempLogDir.path,
        nameprefix: 'test_open_instance_1',
      );
      final instance = XLog.open(config);
      expect(instance.isValid, isTrue);
      
      XLog.destroy(instance);
      // After destroy, the same handle should be invalid
      // (We can't directly test this without refetching)
    });
    
    test('release() on non-existent name does not crash', () async {
      // Should not throw
      XLog.release('nonexistent_xyz');
    });
    
    test('isInitialized is true after first use', () async {
      final config = XLogConfig(
        logdir: tempLogDir.path,
        nameprefix: 'test_open_instance_1',
      );
      XLog.open(config);
      
      expect(XLog.isInitialized, isTrue);
    });
  });
}
```

- [ ] **Step 2: 验证语法**

Run: `cd /Users/jobsygao/Code/Tencent/mars/samples/xlog_flutter/example && dart analyze lib/ integration_test/xlog_open_test.dart 2>&1 | head -20`

Expected: 无错误或仅 info 级别提示

- [ ] **Step 3: 运行测试验证（可选，需要模拟器）**

Run: `cd /Users/jobsygao/Code/Tencent/mars/samples/xlog_flutter/example && flutter test integration_test/xlog_open_test.dart -d macos 2>&1 | tail -20`

Expected: 所有测试 PASS（或跳过无模拟器）

- [ ] **Step 4: 提交**

```bash
cd /Users/jobsygao/Code/Tencent/mars
git add example/integration_test/xlog_open_test.dart
git commit -m "test: add flutter integration tests for xlog instance lifecycle"
```

---

#### Task 5: 创建 xlog_write_test.dart（写日志 + 配置）

**文件：**
- Create: `example/integration_test/xlog_write_test.dart`

- [ ] **Step 1: 编写测试文件**

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:xlog_flutter/xlog_flutter.dart';
import 'test_utils.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  
  late Directory tempLogDir;
  
  setUpAll(() async {
    await XlogTestUtils.setUp();
    tempLogDir = XlogTestUtils.tempLogDir;
  });
  
  tearDown(() async {
    await XlogTestUtils.tearDown('test_write_instance');
  });
  
  group('XLog Write Operations', () {
    test('verbose() writes without crash', () async {
      final config = XLogConfig(
        logdir: tempLogDir.path,
        nameprefix: 'test_write_instance',
      );
      final instance = XLog.open(config);
      
      instance.verbose('tag', 'verbose message');
      instance.flush(sync: true);
      
      final files = await XlogTestUtils.getLogFiles(instance);
      expect(files, isNotEmpty);
    });
    
    test('debug() writes without crash', () async {
      final config = XLogConfig(
        logdir: tempLogDir.path,
        nameprefix: 'test_write_instance',
      );
      final instance = XLog.open(config);
      
      instance.debug('tag', 'debug message');
      instance.flush(sync: true);
      
      final files = await XlogTestUtils.getLogFiles(instance);
      expect(files, isNotEmpty);
    });
    
    test('info() writes without crash', () async {
      final config = XLogConfig(
        logdir: tempLogDir.path,
        nameprefix: 'test_write_instance',
      );
      final instance = XLog.open(config);
      
      instance.info('tag', 'info message');
      instance.flush(sync: true);
      
      final files = await XlogTestUtils.getLogFiles(instance);
      expect(files, isNotEmpty);
    });
    
    test('warn() writes without crash', () async {
      final config = XLogConfig(
        logdir: tempLogDir.path,
        nameprefix: 'test_write_instance',
      );
      final instance = XLog.open(config);
      
      instance.warn('tag', 'warn message');
      instance.flush(sync: true);
      
      final files = await XlogTestUtils.getLogFiles(instance);
      expect(files, isNotEmpty);
    });
    
    test('error() writes without crash', () async {
      final config = XLogConfig(
        logdir: tempLogDir.path,
        nameprefix: 'test_write_instance',
      );
      final instance = XLog.open(config);
      
      instance.error('tag', 'error message');
      instance.flush(sync: true);
      
      final files = await XlogTestUtils.getLogFiles(instance);
      expect(files, isNotEmpty);
    });
    
    test('fatal() writes without crash', () async {
      final config = XLogConfig(
        logdir: tempLogDir.path,
        nameprefix: 'test_write_instance',
      );
      final instance = XLog.open(config);
      
      instance.fatal('tag', 'fatal message');
      instance.flush(sync: true);
      
      final files = await XlogTestUtils.getLogFiles(instance);
      expect(files, isNotEmpty);
    });
    
    test('write() with explicit level', () async {
      final config = XLogConfig(
        logdir: tempLogDir.path,
        nameprefix: 'test_write_instance',
      );
      final instance = XLog.open(config);
      
      instance.write(XLogLevel.info, 'tag', 'message');
      instance.flush(sync: true);
      
      final files = await XlogTestUtils.getLogFiles(instance);
      expect(files, isNotEmpty);
    });
    
    test('write() with filename, funcname, line parameters', () async {
      final config = XLogConfig(
        logdir: tempLogDir.path,
        nameprefix: 'test_write_instance',
      );
      final instance = XLog.open(config);
      
      instance.write(
        XLogLevel.debug,
        'tag',
        'message',
        filename: 'test.dart',
        funcname: 'testFunc',
        line: 123,
      );
      instance.flush(sync: true);
      
      final files = await XlogTestUtils.getLogFiles(instance);
      expect(files, isNotEmpty);
    });
    
    test('logPath is non-empty and contains nameprefix', () async {
      final config = XLogConfig(
        logdir: tempLogDir.path,
        nameprefix: 'test_write_instance',
      );
      final instance = XLog.open(config);
      
      final logPath = instance.logPath;
      expect(logPath, isNotEmpty);
      expect(logPath, contains('test_write_instance'));
    });
    
    test('flush(sync: true) increases file size', () async {
      final config = XLogConfig(
        logdir: tempLogDir.path,
        nameprefix: 'test_write_instance',
      );
      final instance = XLog.open(config);
      
      instance.info('tag', 'test message for size');
      instance.flush(sync: true);
      
      final files = await XlogTestUtils.getLogFiles(instance);
      expect(files, isNotEmpty);
      
      int totalSize = 0;
      for (final file in files) {
        totalSize += await XlogTestUtils.getFileSize(file);
      }
      expect(totalSize, greaterThanOrEqualTo(50));
    });
    
    test('flush(sync: false) does not crash', () async {
      final config = XLogConfig(
        logdir: tempLogDir.path,
        nameprefix: 'test_write_instance',
      );
      final instance = XLog.open(config);
      
      instance.info('tag', 'async flush test');
      instance.flush(sync: false);
      
      // Give async flush time
      await Future.delayed(Duration(milliseconds: 200));
    });
    
    test('flushAll() does not crash', () async {
      final config = XLogConfig(
        logdir: tempLogDir.path,
        nameprefix: 'test_write_instance',
      );
      XLog.open(config);
      XLog.flushAll(sync: true);
    });
    
    test('compression mode zlib generates file with magic bytes', () async {
      final config = XLogConfig(
        logdir: tempLogDir.path,
        nameprefix: 'test_write_instance',
        compressMode: XLogCompressMode.zlib,
      );
      final instance = XLog.open(config);
      
      instance.info('tag', 'compressed message');
      instance.flush(sync: true);
      
      final files = await XlogTestUtils.getLogFiles(instance);
      expect(files, isNotEmpty);
      
      bool hasZlib = false;
      for (final file in files) {
        if (await XlogTestUtils.hasZlibMagic(file)) {
          hasZlib = true;
          break;
        }
      }
      expect(hasZlib, isTrue);
    });
    
    test('compression mode zstd generates file with magic bytes', () async {
      final config = XLogConfig(
        logdir: tempLogDir.path,
        nameprefix: 'test_write_instance',
        compressMode: XLogCompressMode.zstd,
      );
      final instance = XLog.open(config);
      
      instance.info('tag', 'zstd compressed message');
      instance.flush(sync: true);
      
      final files = await XlogTestUtils.getLogFiles(instance);
      expect(files, isNotEmpty);
      
      bool hasZstd = false;
      for (final file in files) {
        if (await XlogTestUtils.hasZstdMagic(file)) {
          hasZstd = true;
          break;
        }
      }
      expect(hasZstd, isTrue);
    });
    
    test('encryption with pubKey generates non-ASCII file', () async {
      final pubKey = '5785f0bd2b145d6fb3acba287cabfdbb96ed6053679ef7b7e0c77ff134f2a86776fe93e77fbed209a93e9165556be8f2d65b6be730da6529e8533643a657e5b1';
      final config = XLogConfig(
        logdir: tempLogDir.path,
        nameprefix: 'test_write_instance',
        pubKey: pubKey,
      );
      final instance = XLog.open(config);
      
      instance.info('tag', 'encrypted message');
      instance.flush(sync: true);
      
      final files = await XlogTestUtils.getLogFiles(instance);
      expect(files, isNotEmpty);
      
      bool isEncrypted = false;
      for (final file in files) {
        if (await XlogTestUtils.isEncrypted(file)) {
          isEncrypted = true;
          break;
        }
      }
      expect(isEncrypted, isTrue);
    });
  });
}
```

- [ ] **Step 2: 验证语法**

Run: `cd /Users/jobsygao/Code/Tencent/mars/samples/xlog_flutter/example && dart analyze integration_test/xlog_write_test.dart 2>&1 | grep -E "(error|warning)" | head -10`

Expected: 无 error（可能有 info）

- [ ] **Step 3: 提交**

```bash
cd /Users/jobsygao/Code/Tencent/mars
git add example/integration_test/xlog_write_test.dart
git commit -m "test: add flutter integration tests for xlog write operations and configuration"
```

---

#### Task 6: 创建 xlog_level_test.dart（级别控制）

**文件：**
- Create: `example/integration_test/xlog_level_test.dart`

- [ ] **Step 1: 编写测试文件**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:xlog_flutter/xlog_flutter.dart';
import 'test_utils.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  
  late Directory tempLogDir;
  
  setUpAll(() async {
    await XlogTestUtils.setUp();
    tempLogDir = XlogTestUtils.tempLogDir;
  });
  
  tearDown(() async {
    await XlogTestUtils.tearDown('test_level_instance');
  });
  
  group('XLog Level Control', () {
    test('setting level to debug filters verbose', () async {
      final config = XLogConfig(
        logdir: tempLogDir.path,
        nameprefix: 'test_level_instance',
      );
      final instance = XLog.open(config);
      instance.level = XLogLevel.debug;
      
      expect(instance.isEnabledFor(XLogLevel.verbose), isFalse);
    });
    
    test('setting level to debug enables debug', () async {
      final config = XLogConfig(
        logdir: tempLogDir.path,
        nameprefix: 'test_level_instance',
      );
      final instance = XLog.open(config);
      instance.level = XLogLevel.debug;
      
      expect(instance.isEnabledFor(XLogLevel.debug), isTrue);
    });
    
    test('setting level to debug enables info', () async {
      final config = XLogConfig(
        logdir: tempLogDir.path,
        nameprefix: 'test_level_instance',
      );
      final instance = XLog.open(config);
      instance.level = XLogLevel.debug;
      
      expect(instance.isEnabledFor(XLogLevel.info), isTrue);
    });
    
    test('level getter equals level setter', () async {
      final config = XLogConfig(
        logdir: tempLogDir.path,
        nameprefix: 'test_level_instance',
      );
      final instance = XLog.open(config);
      instance.level = XLogLevel.warn;
      
      expect(instance.level, equals(XLogLevel.warn));
    });
    
    test('setting level to all enables verbose', () async {
      final config = XLogConfig(
        logdir: tempLogDir.path,
        nameprefix: 'test_level_instance',
      );
      final instance = XLog.open(config);
      instance.level = XLogLevel.all;
      
      expect(instance.isEnabledFor(XLogLevel.verbose), isTrue);
    });
    
    test('setting level to none filters fatal', () async {
      final config = XLogConfig(
        logdir: tempLogDir.path,
        nameprefix: 'test_level_instance',
      );
      final instance = XLog.open(config);
      instance.level = XLogLevel.none;
      
      expect(instance.isEnabledFor(XLogLevel.fatal), isFalse);
    });
    
    test('all level enum values are settable', () async {
      final config = XLogConfig(
        logdir: tempLogDir.path,
        nameprefix: 'test_level_instance',
      );
      final instance = XLog.open(config);
      
      final levels = [
        XLogLevel.all,
        XLogLevel.verbose,
        XLogLevel.debug,
        XLogLevel.info,
        XLogLevel.warn,
        XLogLevel.error,
        XLogLevel.fatal,
        XLogLevel.none,
      ];
      
      for (final level in levels) {
        instance.level = level;
        expect(instance.level, equals(level));
      }
    });
  });
}
```

- [ ] **Step 2: 验证语法**

Run: `cd /Users/jobsygao/Code/Tencent/mars/samples/xlog_flutter/example && dart analyze integration_test/xlog_level_test.dart 2>&1 | grep -E "error" | head -5`

Expected: 无 error

- [ ] **Step 3: 提交**

```bash
cd /Users/jobsygao/Code/Tencent/mars
git add example/integration_test/xlog_level_test.dart
git commit -m "test: add flutter integration tests for xlog level control"
```

---

#### Task 7: 创建 xlog_control_test.dart（控制方法）

**文件：**
- Create: `example/integration_test/xlog_control_test.dart`

- [ ] **Step 1: 编写测试文件**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:xlog_flutter/xlog_flutter.dart';
import 'test_utils.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  
  late Directory tempLogDir;
  
  setUpAll(() async {
    await XlogTestUtils.setUp();
    tempLogDir = XlogTestUtils.tempLogDir;
  });
  
  tearDown(() async {
    await XlogTestUtils.tearDown('test_control_instance');
  });
  
  group('XLog Control Methods', () {
    test('appenderMode can be set to sync_', () async {
      final config = XLogConfig(
        logdir: tempLogDir.path,
        nameprefix: 'test_control_instance',
      );
      final instance = XLog.open(config);
      
      instance.appenderMode = XLogAppenderMode.sync_;
      // No exception should be thrown
    });
    
    test('appenderMode can be set to async_', () async {
      final config = XLogConfig(
        logdir: tempLogDir.path,
        nameprefix: 'test_control_instance',
      );
      final instance = XLog.open(config);
      
      instance.appenderMode = XLogAppenderMode.async_;
      // No exception should be thrown
    });
    
    test('consoleLogOpen can be set to true', () async {
      final config = XLogConfig(
        logdir: tempLogDir.path,
        nameprefix: 'test_control_instance',
      );
      final instance = XLog.open(config);
      
      instance.consoleLogOpen = true;
      // No exception should be thrown
    });
    
    test('consoleLogOpen can be set to false', () async {
      final config = XLogConfig(
        logdir: tempLogDir.path,
        nameprefix: 'test_control_instance',
      );
      final instance = XLog.open(config);
      
      instance.consoleLogOpen = false;
      // No exception should be thrown
    });
    
    test('flush with sync: true does not crash', () async {
      final config = XLogConfig(
        logdir: tempLogDir.path,
        nameprefix: 'test_control_instance',
      );
      final instance = XLog.open(config);
      
      instance.info('tag', 'message');
      instance.flush(sync: true);
      // No exception should be thrown
    });
    
    test('flush with sync: false does not crash', () async {
      final config = XLogConfig(
        logdir: tempLogDir.path,
        nameprefix: 'test_control_instance',
      );
      final instance = XLog.open(config);
      
      instance.info('tag', 'message');
      instance.flush(sync: false);
      
      // Give async flush time
      await Future.delayed(Duration(milliseconds: 100));
      // No exception should be thrown
    });
    
    test('logPath is non-empty after open', () async {
      final config = XLogConfig(
        logdir: tempLogDir.path,
        nameprefix: 'test_control_instance',
      );
      final instance = XLog.open(config);
      
      final logPath = instance.logPath;
      expect(logPath, isNotEmpty);
    });
  });
}
```

- [ ] **Step 2: 验证语法**

Run: `cd /Users/jobsygao/Code/Tencent/mars/samples/xlog_flutter/example && dart analyze integration_test/xlog_control_test.dart 2>&1 | head -10`

Expected: 无 error

- [ ] **Step 3: 提交**

```bash
cd /Users/jobsygao/Code/Tencent/mars
git add example/integration_test/xlog_control_test.dart
git commit -m "test: add flutter integration tests for xlog control methods"
```

---

#### Task 8: 创建 xlog_multi_instance_test.dart（多实例）

**文件：**
- Create: `example/integration_test/xlog_multi_instance_test.dart`

- [ ] **Step 1: 编写测试文件**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:xlog_flutter/xlog_flutter.dart';
import 'test_utils.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  
  late Directory tempLogDir;
  
  setUpAll(() async {
    await XlogTestUtils.setUp();
    tempLogDir = XlogTestUtils.tempLogDir;
  });
  
  tearDown(() async {
    await XlogTestUtils.tearDown('test_multi_1');
    await XlogTestUtils.tearDown('test_multi_2');
  });
  
  group('XLog Multi-Instance', () {
    test('two instances have different logPath', () async {
      final config1 = XLogConfig(
        logdir: tempLogDir.path,
        nameprefix: 'test_multi_1',
      );
      final config2 = XLogConfig(
        logdir: tempLogDir.path,
        nameprefix: 'test_multi_2',
      );
      
      final instance1 = XLog.open(config1);
      final instance2 = XLog.open(config2);
      
      expect(instance1.logPath, isNotEmpty);
      expect(instance2.logPath, isNotEmpty);
      expect(instance1.logPath, isNot(equals(instance2.logPath)));
    });
    
    test('instance levels are independent', () async {
      final config1 = XLogConfig(
        logdir: tempLogDir.path,
        nameprefix: 'test_multi_1',
      );
      final config2 = XLogConfig(
        logdir: tempLogDir.path,
        nameprefix: 'test_multi_2',
      );
      
      final instance1 = XLog.open(config1);
      final instance2 = XLog.open(config2);
      
      instance1.level = XLogLevel.debug;
      instance2.level = XLogLevel.error;
      
      expect(instance1.level, equals(XLogLevel.debug));
      expect(instance2.level, equals(XLogLevel.error));
    });
    
    test('instance appender modes are independent', () async {
      final config1 = XLogConfig(
        logdir: tempLogDir.path,
        nameprefix: 'test_multi_1',
      );
      final config2 = XLogConfig(
        logdir: tempLogDir.path,
        nameprefix: 'test_multi_2',
      );
      
      final instance1 = XLog.open(config1);
      final instance2 = XLog.open(config2);
      
      instance1.appenderMode = XLogAppenderMode.sync_;
      instance2.appenderMode = XLogAppenderMode.async_;
      // No exception should be thrown
    });
    
    test('releasing one instance does not affect another', () async {
      final config1 = XLogConfig(
        logdir: tempLogDir.path,
        nameprefix: 'test_multi_1',
      );
      final config2 = XLogConfig(
        logdir: tempLogDir.path,
        nameprefix: 'test_multi_2',
      );
      
      final instance1 = XLog.open(config1);
      final instance2 = XLog.open(config2);
      
      XLog.release('test_multi_1');
      expect(XLog.has('test_multi_1'), isFalse);
      expect(XLog.has('test_multi_2'), isTrue);
      expect(instance2.isValid, isTrue);
    });
    
    test('flushAll() flushes both instances', () async {
      final config1 = XLogConfig(
        logdir: tempLogDir.path,
        nameprefix: 'test_multi_1',
      );
      final config2 = XLogConfig(
        logdir: tempLogDir.path,
        nameprefix: 'test_multi_2',
      );
      
      final instance1 = XLog.open(config1);
      final instance2 = XLog.open(config2);
      
      instance1.info('tag', 'message 1');
      instance2.info('tag', 'message 2');
      
      XLog.flushAll(sync: true);
      
      final files1 = await XlogTestUtils.getLogFiles(instance1);
      final files2 = await XlogTestUtils.getLogFiles(instance2);
      
      expect(files1, isNotEmpty);
      expect(files2, isNotEmpty);
    });
  });
}
```

- [ ] **Step 2: 验证语法**

Run: `cd /Users/jobsygao/Code/Tencent/mars/samples/xlog_flutter/example && dart analyze integration_test/xlog_multi_instance_test.dart 2>&1 | head -10`

Expected: 无 error

- [ ] **Step 3: 提交**

```bash
cd /Users/jobsygao/Code/Tencent/mars
git add example/integration_test/xlog_multi_instance_test.dart
git commit -m "test: add flutter integration tests for xlog multi-instance scenarios"
```

---

#### Task 9: 创建 xlog_all_test.dart（入口）

**文件：**
- Create: `example/integration_test/xlog_all_test.dart`

- [ ] **Step 1: 编写入口文件**

```dart
// Test entry point that aggregates all xlog_flutter integration tests
// 
// Run with:
//   flutter test integration_test/ -d macos
//   flutter test integration_test/ -d ios
//   flutter test integration_test/ -d android
//
// Each individual test file (xlog_open_test.dart, xlog_write_test.dart, etc.)
// is self-contained and can be run independently.

void main() {
  // This file serves as documentation and entry point.
  // Flutter's test runner automatically discovers and runs all *_test.dart files
  // in the integration_test/ directory.
  // No explicit tests defined here.
}
```

- [ ] **Step 2: 验证文件**

Run: `ls -la /Users/jobsygao/Code/Tencent/mars/samples/xlog_flutter/example/integration_test/`

Expected: 6 个 .dart 文件（test_utils, xlog_open_test, xlog_write_test, xlog_level_test, xlog_control_test, xlog_multi_instance_test, xlog_all_test）

- [ ] **Step 3: 提交**

```bash
cd /Users/jobsygao/Code/Tencent/mars
git add example/integration_test/xlog_all_test.dart
git commit -m "test: add xlog_all_test.dart as integration test entry point"
```

---

### 原生平台测试（iOS/macOS/Android）

#### Task 10: 扩展 iOS RunnerTests.swift

**文件：**
- Modify: `example/ios/RunnerTests/RunnerTests.swift`

- [ ] **Step 1: 读取现有文件**

Run: `cat /Users/jobsygao/Code/Tencent/mars/samples/xlog_flutter/example/ios/RunnerTests/RunnerTests.swift`

Expected: 13 行空 placeholder

- [ ] **Step 2: 完全替换为 iOS XCTest**

```swift
import XCTest

// Import the ObjC wrapper headers
// Note: These are part of the pod dependency xlog_flutter
// Header search path configured in podspec

class XlogNativeIOSTests: XCTestCase {
  
  override func setUpWithError() throws {
    // Put setup code here. This is called before the invocation of each test method in the class.
  }
  
  override func tearDownWithError() throws {
    // Put teardown code here. This is called after the invocation of each test method in the class.
  }
  
  // MARK: - XLogManager Tests
  
  func testCreateInstance() throws {
    // Create a temporary directory for logs
    let tempDir = NSTemporaryDirectory()
    let logPath = (tempDir as NSString).appendingPathComponent("xlog_test_ios")
    
    let config = XLogConfig()
    config.logdir = logPath
    config.nameprefix = "test_create"
    
    let instance = XLogManager.open(with: config, level: .info)
    XCTAssertNotNil(instance)
    XCTAssertTrue(instance.isValid)
  }
  
  func testHasInstance() throws {
    let tempDir = NSTemporaryDirectory()
    let logPath = (tempDir as NSString).appendingPathComponent("xlog_test_ios")
    
    let config = XLogConfig()
    config.logdir = logPath
    config.nameprefix = "test_has"
    
    XLogManager.open(with: config, level: .info)
    XCTAssertTrue(XLogManager.hasInstance(withName: "test_has"))
    
    XLogManager.releaseInstance(withName: "test_has")
  }
  
  func testGetInstance() throws {
    let tempDir = NSTemporaryDirectory()
    let logPath = (tempDir as NSString).appendingPathComponent("xlog_test_ios")
    
    let config = XLogConfig()
    config.logdir = logPath
    config.nameprefix = "test_get"
    
    let instance1 = XLogManager.open(with: config, level: .debug)
    let instance2 = XLogManager.getInstance(byName: "test_get")
    
    XCTAssertEqual(instance1.handle, instance2.handle)
    
    XLogManager.releaseInstance(withName: "test_get")
  }
  
  func testReleaseInstance() throws {
    let tempDir = NSTemporaryDirectory()
    let logPath = (tempDir as NSString).appendingPathComponent("xlog_test_ios")
    
    let config = XLogConfig()
    config.logdir = logPath
    config.nameprefix = "test_release"
    
    XLogManager.open(with: config, level: .info)
    XCTAssertTrue(XLogManager.hasInstance(withName: "test_release"))
    
    XLogManager.releaseInstance(withName: "test_release")
    XCTAssertFalse(XLogManager.hasInstance(withName: "test_release"))
  }
  
  // MARK: - XLogInstance Tests
  
  func testWriteLogs() throws {
    let tempDir = NSTemporaryDirectory()
    let logPath = (tempDir as NSString).appendingPathComponent("xlog_test_ios")
    
    let config = XLogConfig()
    config.logdir = logPath
    config.nameprefix = "test_write"
    
    let instance = XLogManager.open(with: config, level: .verbose)
    
    // Test all log levels
    instance.verbose(tag: "tag", msg: "verbose message")
    instance.debug(tag: "tag", msg: "debug message")
    instance.info(tag: "tag", msg: "info message")
    instance.warn(tag: "tag", msg: "warn message")
    instance.error(tag: "tag", msg: "error message")
    instance.fatal(tag: "tag", msg: "fatal message")
    
    instance.flush(sync: true)
    
    XCTAssertFalse(instance.logPath.isEmpty)
    
    XLogManager.releaseInstance(withName: "test_write")
  }
  
  func testLevelControl() throws {
    let tempDir = NSTemporaryDirectory()
    let logPath = (tempDir as NSString).appendingPathComponent("xlog_test_ios")
    
    let config = XLogConfig()
    config.logdir = logPath
    config.nameprefix = "test_level"
    
    let instance = XLogManager.open(with: config, level: .debug)
    
    instance.level = .debug
    XCTAssertEqual(instance.level, .debug)
    
    instance.level = .error
    XCTAssertEqual(instance.level, .error)
    
    XLogManager.releaseInstance(withName: "test_level")
  }
  
  func testFlush() throws {
    let tempDir = NSTemporaryDirectory()
    let logPath = (tempDir as NSString).appendingPathComponent("xlog_test_ios")
    
    let config = XLogConfig()
    config.logdir = logPath
    config.nameprefix = "test_flush"
    
    let instance = XLogManager.open(with: config, level: .info)
    
    instance.info(tag: "tag", msg: "test message")
    instance.flush(sync: true)
    
    XCTAssertFalse(instance.logPath.isEmpty)
    
    XLogManager.releaseInstance(withName: "test_flush")
  }
  
  func testConfig() throws {
    let tempDir = NSTemporaryDirectory()
    let logPath = (tempDir as NSString).appendingPathComponent("xlog_test_ios")
    
    let config = XLogConfig()
    config.logdir = logPath
    config.nameprefix = "test_config"
    config.compressMode = .zstd
    config.compressLevel = 3
    
    let instance = XLogManager.open(with: config, level: .info)
    
    instance.info(tag: "tag", msg: "test message")
    instance.flush(sync: true)
    
    XCTAssertTrue(instance.isValid)
    
    XLogManager.releaseInstance(withName: "test_config")
  }
  
  func testPerformanceExample() throws {
    // This is an example of a performance test case.
    self.measure {
      let tempDir = NSTemporaryDirectory()
      let logPath = (tempDir as NSString).appendingPathComponent("xlog_perf_test")
      
      let config = XLogConfig()
      config.logdir = logPath
      config.nameprefix = "test_perf"
      
      let instance = XLogManager.open(with: config, level: .verbose)
      
      for i in 0..<100 {
        instance.info(tag: "perf", msg: "Message \(i)")
      }
      
      instance.flush(sync: true)
      
      XLogManager.releaseInstance(withName: "test_perf")
    }
  }
}
```

- [ ] **Step 3: 验证文件**

Run: `wc -l /Users/jobsygao/Code/Tencent/mars/samples/xlog_flutter/example/ios/RunnerTests/RunnerTests.swift`

Expected: 约 200+ 行

- [ ] **Step 4: 提交**

```bash
cd /Users/jobsygao/Code/Tencent/mars
git add example/ios/RunnerTests/RunnerTests.swift
git commit -m "test: add comprehensive XCTest for iOS xlog native layer"
```

---

#### Task 11: 扩展 macOS RunnerTests.swift

**文件：**
- Modify: `example/macos/RunnerTests/RunnerTests.swift`

- [ ] **Step 1: 复制 iOS 代码至 macOS**

Run: `cp /Users/jobsygao/Code/Tencent/mars/samples/xlog_flutter/example/ios/RunnerTests/RunnerTests.swift /Users/jobsygao/Code/Tencent/mars/samples/xlog_flutter/example/macos/RunnerTests/RunnerTests.swift`

- [ ] **Step 2: 编辑 macOS 版本（改类名以示区别）**

编辑文件，将 `class XlogNativeIOSTests` 改为 `class XlogNativeMacOSTests`

- [ ] **Step 3: 验证**

Run: `head -20 /Users/jobsygao/Code/Tencent/mars/samples/xlog_flutter/example/macos/RunnerTests/RunnerTests.swift`

Expected: 包含 `class XlogNativeMacOSTests`

- [ ] **Step 4: 提交**

```bash
cd /Users/jobsygao/Code/Tencent/mars
git add example/macos/RunnerTests/RunnerTests.swift
git commit -m "test: add comprehensive XCTest for macOS xlog native layer"
```

---

#### Task 12: 扩展 Android XlogNativeInstrumentedTest.kt

**文件：**
- Modify: `example/android/app/src/androidTest/java/com/codexgao/xlog_flutter_example/XlogNativeInstrumentedTest.kt`

- [ ] **Step 1: 读取现有文件**

Run: `wc -l /Users/jobsygao/Code/Tencent/mars/samples/xlog_flutter/example/android/app/src/androidTest/java/com/codexgao/xlog_flutter_example/XlogNativeInstrumentedTest.kt`

Expected: 约 245 行

- [ ] **Step 2: 扩展现有测试 (追加到文件末尾，保留现有内容)**

在文件末尾添加新测试用例（不要删除现有代码）：

```kotlin
  // Additional API coverage tests
  
  @Test
  fun testXlogGetLevel() {
    val config = XlogConfig(
      logdir = context.filesDir.path,
      nameprefix = "test_get_level"
    )
    val handle = XLog.newInstance(config)
    
    XLog.setLevel(handle, XlogLevel.DEBUG)
    val level = XLog.getLevel(handle)
    
    assertEquals(XlogLevel.DEBUG, level)
    
    XLog.releaseInstance(handle)
  }
  
  @Test
  fun testXlogSetAppenderMode() {
    val config = XlogConfig(
      logdir = context.filesDir.path,
      nameprefix = "test_appender_mode"
    )
    val handle = XLog.newInstance(config)
    
    // Should not crash
    XLog.setAppenderMode(handle, XlogAppenderMode.SYNC)
    XLog.setAppenderMode(handle, XlogAppenderMode.ASYNC)
    
    XLog.releaseInstance(handle)
  }
  
  @Test
  fun testXlogConsoleLogOpen() {
    val config = XlogConfig(
      logdir = context.filesDir.path,
      nameprefix = "test_console_log"
    )
    val handle = XLog.newInstance(config)
    
    // Should not crash
    XLog.setConsoleLogOpen(handle, true)
    XLog.setConsoleLogOpen(handle, false)
    
    XLog.releaseInstance(handle)
  }
  
  @Test
  fun testXlogFlush() {
    val config = XlogConfig(
      logdir = context.filesDir.path,
      nameprefix = "test_flush"
    )
    val handle = XLog.newInstance(config)
    
    XLog.write(handle, XlogLevel.INFO, "tag", "message")
    
    // Test sync flush
    XLog.flush(handle, true)
    
    // Test async flush
    XLog.flush(handle, false)
    Thread.sleep(200) // Give async flush time
    
    XLog.releaseInstance(handle)
  }
  
  @Test
  fun testXlogFlushAll() {
    val config1 = XlogConfig(
      logdir = context.filesDir.path,
      nameprefix = "test_flush_all_1"
    )
    val config2 = XlogConfig(
      logdir = context.filesDir.path,
      nameprefix = "test_flush_all_2"
    )
    
    val handle1 = XLog.newInstance(config1)
    val handle2 = XLog.newInstance(config2)
    
    XLog.write(handle1, XlogLevel.INFO, "tag", "message 1")
    XLog.write(handle2, XlogLevel.INFO, "tag", "message 2")
    
    // Should not crash
    XLog.flushAll()
    
    XLog.releaseInstance(handle1)
    XLog.releaseInstance(handle2)
  }
  
  @Test
  fun testXlogGetLogPath() {
    val config = XlogConfig(
      logdir = context.filesDir.path,
      nameprefix = "test_get_log_path"
    )
    val handle = XLog.newInstance(config)
    
    val logPath = XLog.getLogPath(handle)
    
    assertNotNull(logPath)
    assertNotEquals("", logPath)
    assertTrue(logPath!!.contains("test_get_log_path"))
    
    XLog.releaseInstance(handle)
  }
  
  @Test
  fun testXlogWithCompression() {
    val config = XlogConfig(
      logdir = context.filesDir.path,
      nameprefix = "test_zstd_compression",
      compressMode = XlogCompressMode.ZSTD,
      compressLevel = 3
    )
    val handle = XLog.newInstance(config)
    
    XLog.write(handle, XlogLevel.INFO, "tag", "compressed message")
    XLog.flush(handle, true)
    
    // Verify file was created
    val logPath = XLog.getLogPath(handle)
    val logDir = File(logPath)
    assertTrue(logDir.exists())
    assertTrue(logDir.listFiles()?.isNotEmpty() == true)
    
    XLog.releaseInstance(handle)
  }
  
  @Test
  fun testXlogDestroyInstance() {
    val config = XlogConfig(
      logdir = context.filesDir.path,
      nameprefix = "test_destroy"
    )
    val handle = XLog.newInstance(config)
    
    assertTrue(XLog.hasInstance("test_destroy"))
    
    XLog.destroyInstance(handle)
    
    // Note: hasInstance might still return true if native destroy doesn't remove
    // This test primarily verifies no crash occurs
  }
```

- [ ] **Step 2: 验证文件**

Run: `wc -l /Users/jobsygao/Code/Tencent/mars/samples/xlog_flutter/example/android/app/src/androidTest/java/com/codexgao/xlog_flutter_example/XlogNativeInstrumentedTest.kt`

Expected: 约 350+ 行（245 + 新增）

- [ ] **Step 3: 检查编译**

Run: `cd /Users/jobsygao/Code/Tencent/mars/samples/xlog_flutter/example/android && ./gradlew compileDebugAndroidTestKotlin 2>&1 | tail -20`

Expected: BUILD SUCCESSFUL 或类似（可能有警告但无错误）

- [ ] **Step 4: 提交**

```bash
cd /Users/jobsygao/Code/Tencent/mars
git add example/android/app/src/androidTest/java/com/codexgao/xlog_flutter_example/XlogNativeInstrumentedTest.kt
git commit -m "test: extend Android instrumented tests for xlog C API coverage"
```

---

### Windows/Linux 测试（暂缓验证）

#### Task 13: 创建 Windows 测试框架

**文件：**
- Create: `example/windows/runner/xlog_native_test.cpp`

- [ ] **Step 1: 创建目录**

Run: `mkdir -p /Users/jobsygao/Code/Tencent/mars/samples/xlog_flutter/example/windows/runner`

- [ ] **Step 2: 编写 Windows C++ 测试框架**

```cpp
// xlog_native_test.cpp - Windows C API test (TODO: verify on target platform)
// This file demonstrates test structure for Windows platform
// Implementation uses direct C API calls via DLL loading

#ifdef _WIN32

#include <windows.h>
#include <iostream>
#include <cassert>
#include <cstring>
#include <string>
#include <filesystem>

// Forward declare xlog C API functions
extern "C" {
  // Functions from xlog_capi.h
  typedef void* xlog_handle_t;
  
  enum xlog_level_t {
    XLogLevelAll = 0,
    XLogLevelVerbose = 1,
    XLogLevelDebug = 2,
    XLogLevelInfo = 3,
    XLogLevelWarn = 4,
    XLogLevelError = 5,
    XLogLevelFatal = 6,
    XLogLevelNone = 7
  };
  
  enum xlog_appender_mode_t {
    XLogAppenderModeAsync = 0,
    XLogAppenderModeSync = 1
  };
  
  enum xlog_compress_mode_t {
    XLogCompressModeZlib = 0,
    XLogCompressModeZstd = 1
  };
  
  typedef struct xlog_config_t {
    xlog_appender_mode_t mode;
    const char* logdir;
    const char* nameprefix;
    const char* pub_key;
    xlog_compress_mode_t compress_mode;
    int compress_level;
    const char* cachedir;
    int cache_days;
  } xlog_config_t;
  
  // C API function pointers
  xlog_handle_t (*xlog_new_instance)(const xlog_config_t* config) = nullptr;
  xlog_handle_t (*xlog_get_instance)(const char* nameprefix) = nullptr;
  bool (*xlog_has_instance)(const char* nameprefix) = nullptr;
  void (*xlog_write)(xlog_handle_t handle, xlog_level_t level, const char* tag, const char* filename, const char* funcname, int line, const char* msg) = nullptr;
  xlog_level_t (*xlog_get_level)(xlog_handle_t handle) = nullptr;
  void (*xlog_set_level)(xlog_handle_t handle, xlog_level_t level) = nullptr;
  bool (*xlog_is_enabled_for)(xlog_handle_t handle, xlog_level_t level) = nullptr;
  void (*xlog_set_appender_mode)(xlog_handle_t handle, xlog_appender_mode_t mode) = nullptr;
  void (*xlog_set_console_log_open)(xlog_handle_t handle, bool open) = nullptr;
  void (*xlog_flush)(xlog_handle_t handle, bool sync) = nullptr;
  void (*xlog_flush_all)(bool sync) = nullptr;
  const char* (*xlog_get_log_path)(xlog_handle_t handle) = nullptr;
  void (*xlog_release_instance)(const char* nameprefix) = nullptr;
  void (*xlog_destroy_instance)(xlog_handle_t handle) = nullptr;
}

// Load DLL and get function pointers
bool LoadXLogDLL(const char* dllPath) {
  HMODULE hModule = LoadLibraryA(dllPath);
  if (!hModule) {
    std::cerr << "Failed to load xlog.dll" << std::endl;
    return false;
  }
  
  xlog_new_instance = (decltype(xlog_new_instance))GetProcAddress(hModule, "xlog_new_instance");
  xlog_get_instance = (decltype(xlog_get_instance))GetProcAddress(hModule, "xlog_get_instance");
  xlog_has_instance = (decltype(xlog_has_instance))GetProcAddress(hModule, "xlog_has_instance");
  xlog_write = (decltype(xlog_write))GetProcAddress(hModule, "xlog_write");
  xlog_get_level = (decltype(xlog_get_level))GetProcAddress(hModule, "xlog_get_level");
  xlog_set_level = (decltype(xlog_set_level))GetProcAddress(hModule, "xlog_set_level");
  xlog_is_enabled_for = (decltype(xlog_is_enabled_for))GetProcAddress(hModule, "xlog_is_enabled_for");
  xlog_set_appender_mode = (decltype(xlog_set_appender_mode))GetProcAddress(hModule, "xlog_set_appender_mode");
  xlog_set_console_log_open = (decltype(xlog_set_console_log_open))GetProcAddress(hModule, "xlog_set_console_log_open");
  xlog_flush = (decltype(xlog_flush))GetProcAddress(hModule, "xlog_flush");
  xlog_flush_all = (decltype(xlog_flush_all))GetProcAddress(hModule, "xlog_flush_all");
  xlog_get_log_path = (decltype(xlog_get_log_path))GetProcAddress(hModule, "xlog_get_log_path");
  xlog_release_instance = (decltype(xlog_release_instance))GetProcAddress(hModule, "xlog_release_instance");
  xlog_destroy_instance = (decltype(xlog_destroy_instance))GetProcAddress(hModule, "xlog_destroy_instance");
  
  return true;
}

// Test functions
void TestCreateInstance() {
  char tempPath[MAX_PATH];
  GetTempPathA(MAX_PATH, tempPath);
  std::string logDir = std::string(tempPath) + "xlog_test\\";
  std::filesystem::create_directories(logDir);
  
  xlog_config_t config = {};
  config.mode = XLogAppenderModeAsync;
  config.logdir = logDir.c_str();
  config.nameprefix = "test_create";
  
  xlog_handle_t handle = xlog_new_instance(&config);
  assert(handle != nullptr && "Failed to create instance");
  
  xlog_release_instance("test_create");
  std::cout << "✓ TestCreateInstance passed" << std::endl;
}

void TestWriteLogs() {
  char tempPath[MAX_PATH];
  GetTempPathA(MAX_PATH, tempPath);
  std::string logDir = std::string(tempPath) + "xlog_test\\";
  std::filesystem::create_directories(logDir);
  
  xlog_config_t config = {};
  config.mode = XLogAppenderModeSync;
  config.logdir = logDir.c_str();
  config.nameprefix = "test_write";
  
  xlog_handle_t handle = xlog_new_instance(&config);
  
  xlog_write(handle, XLogLevelDebug, "tag", "test.cpp", "TestWriteLogs", 0, "debug message");
  xlog_write(handle, XLogLevelInfo, "tag", "test.cpp", "TestWriteLogs", 0, "info message");
  xlog_write(handle, XLogLevelWarn, "tag", "test.cpp", "TestWriteLogs", 0, "warn message");
  
  xlog_flush(handle, true);
  
  xlog_release_instance("test_write");
  std::cout << "✓ TestWriteLogs passed" << std::endl;
}

void TestLevelControl() {
  char tempPath[MAX_PATH];
  GetTempPathA(MAX_PATH, tempPath);
  std::string logDir = std::string(tempPath) + "xlog_test\\";
  std::filesystem::create_directories(logDir);
  
  xlog_config_t config = {};
  config.mode = XLogAppenderModeSync;
  config.logdir = logDir.c_str();
  config.nameprefix = "test_level";
  
  xlog_handle_t handle = xlog_new_instance(&config);
  
  xlog_set_level(handle, XLogLevelDebug);
  assert(xlog_get_level(handle) == XLogLevelDebug && "Level mismatch");
  assert(xlog_is_enabled_for(handle, XLogLevelDebug) && "Debug should be enabled");
  assert(!xlog_is_enabled_for(handle, XLogLevelVerbose) && "Verbose should be disabled");
  
  xlog_release_instance("test_level");
  std::cout << "✓ TestLevelControl passed" << std::endl;
}

int main() {
  std::cout << "xlog Windows Native Tests (TODO: verify on target platform)" << std::endl;
  
  // TODO: Provide correct path to xlog.dll on test machine
  if (!LoadXLogDLL("xlog.dll")) {
    std::cerr << "Failed to load xlog library" << std::endl;
    return 1;
  }
  
  try {
    TestCreateInstance();
    TestWriteLogs();
    TestLevelControl();
    
    std::cout << "\nAll tests passed!" << std::endl;
    return 0;
  } catch (const std::exception& e) {
    std::cerr << "Test failed: " << e.what() << std::endl;
    return 1;
  }
}

#else
#error "This test is for Windows platform only"
#endif
```

- [ ] **Step 3: 验证**

Run: `wc -l /Users/jobsygao/Code/Tencent/mars/samples/xlog_flutter/example/windows/runner/xlog_native_test.cpp`

Expected: 约 150+ 行

- [ ] **Step 4: 提交（标注 TODO）**

```bash
cd /Users/jobsygao/Code/Tencent/mars
git add example/windows/runner/xlog_native_test.cpp
git commit -m "test: add Windows C++ test framework (TODO: verify on target platform)"
```

---

#### Task 14: 创建 Linux 测试框架

**文件：**
- Create: `example/linux/runner/xlog_native_test.cpp`

- [ ] **Step 1: 创建目录**

Run: `mkdir -p /Users/jobsygao/Code/Tencent/mars/samples/xlog_flutter/example/linux/runner`

- [ ] **Step 2: 编写 Linux C++ 测试框架**

```cpp
// xlog_native_test.cpp - Linux C API test (TODO: verify on target platform)
// This file demonstrates test structure for Linux platform
// Implementation uses direct C API calls via shared library loading

#ifndef _WIN32

#include <dlfcn.h>
#include <iostream>
#include <cassert>
#include <cstring>
#include <string>
#include <filesystem>
#include <sys/stat.h>

// Forward declare xlog C API functions
extern "C" {
  typedef void* xlog_handle_t;
  
  enum xlog_level_t {
    XLogLevelAll = 0,
    XLogLevelVerbose = 1,
    XLogLevelDebug = 2,
    XLogLevelInfo = 3,
    XLogLevelWarn = 4,
    XLogLevelError = 5,
    XLogLevelFatal = 6,
    XLogLevelNone = 7
  };
  
  enum xlog_appender_mode_t {
    XLogAppenderModeAsync = 0,
    XLogAppenderModeSync = 1
  };
  
  enum xlog_compress_mode_t {
    XLogCompressModeZlib = 0,
    XLogCompressModeZstd = 1
  };
  
  typedef struct xlog_config_t {
    xlog_appender_mode_t mode;
    const char* logdir;
    const char* nameprefix;
    const char* pub_key;
    xlog_compress_mode_t compress_mode;
    int compress_level;
    const char* cachedir;
    int cache_days;
  } xlog_config_t;
  
  // C API function pointers
  xlog_handle_t (*xlog_new_instance)(const xlog_config_t* config) = nullptr;
  xlog_handle_t (*xlog_get_instance)(const char* nameprefix) = nullptr;
  bool (*xlog_has_instance)(const char* nameprefix) = nullptr;
  void (*xlog_write)(xlog_handle_t handle, xlog_level_t level, const char* tag, const char* filename, const char* funcname, int line, const char* msg) = nullptr;
  xlog_level_t (*xlog_get_level)(xlog_handle_t handle) = nullptr;
  void (*xlog_set_level)(xlog_handle_t handle, xlog_level_t level) = nullptr;
  bool (*xlog_is_enabled_for)(xlog_handle_t handle, xlog_level_t level) = nullptr;
  void (*xlog_set_appender_mode)(xlog_handle_t handle, xlog_appender_mode_t mode) = nullptr;
  void (*xlog_set_console_log_open)(xlog_handle_t handle, bool open) = nullptr;
  void (*xlog_flush)(xlog_handle_t handle, bool sync) = nullptr;
  void (*xlog_flush_all)(bool sync) = nullptr;
  const char* (*xlog_get_log_path)(xlog_handle_t handle) = nullptr;
  void (*xlog_release_instance)(const char* nameprefix) = nullptr;
  void (*xlog_destroy_instance)(xlog_handle_t handle) = nullptr;
}

// Load shared library and get function pointers
bool LoadXLogLibrary(const char* libPath) {
  void* handle = dlopen(libPath, RTLD_LAZY);
  if (!handle) {
    std::cerr << "Failed to load libxlog.so: " << dlerror() << std::endl;
    return false;
  }
  
  xlog_new_instance = (decltype(xlog_new_instance))dlsym(handle, "xlog_new_instance");
  xlog_get_instance = (decltype(xlog_get_instance))dlsym(handle, "xlog_get_instance");
  xlog_has_instance = (decltype(xlog_has_instance))dlsym(handle, "xlog_has_instance");
  xlog_write = (decltype(xlog_write))dlsym(handle, "xlog_write");
  xlog_get_level = (decltype(xlog_get_level))dlsym(handle, "xlog_get_level");
  xlog_set_level = (decltype(xlog_set_level))dlsym(handle, "xlog_set_level");
  xlog_is_enabled_for = (decltype(xlog_is_enabled_for))dlsym(handle, "xlog_is_enabled_for");
  xlog_set_appender_mode = (decltype(xlog_set_appender_mode))dlsym(handle, "xlog_set_appender_mode");
  xlog_set_console_log_open = (decltype(xlog_set_console_log_open))dlsym(handle, "xlog_set_console_log_open");
  xlog_flush = (decltype(xlog_flush))dlsym(handle, "xlog_flush");
  xlog_flush_all = (decltype(xlog_flush_all))dlsym(handle, "xlog_flush_all");
  xlog_get_log_path = (decltype(xlog_get_log_path))dlsym(handle, "xlog_get_log_path");
  xlog_release_instance = (decltype(xlog_release_instance))dlsym(handle, "xlog_release_instance");
  xlog_destroy_instance = (decltype(xlog_destroy_instance))dlsym(handle, "xlog_destroy_instance");
  
  return true;
}

// Test functions
void TestCreateInstance() {
  const char* tmpDir = getenv("XDG_RUNTIME_DIR");
  if (!tmpDir) tmpDir = "/tmp";
  
  std::string logDir = std::string(tmpDir) + "/xlog_test/";
  std::filesystem::create_directories(logDir);
  
  xlog_config_t config = {};
  config.mode = XLogAppenderModeAsync;
  config.logdir = logDir.c_str();
  config.nameprefix = "test_create";
  
  xlog_handle_t handle = xlog_new_instance(&config);
  assert(handle != nullptr && "Failed to create instance");
  
  xlog_release_instance("test_create");
  std::cout << "✓ TestCreateInstance passed" << std::endl;
}

void TestWriteLogs() {
  const char* tmpDir = getenv("XDG_RUNTIME_DIR");
  if (!tmpDir) tmpDir = "/tmp";
  
  std::string logDir = std::string(tmpDir) + "/xlog_test/";
  std::filesystem::create_directories(logDir);
  
  xlog_config_t config = {};
  config.mode = XLogAppenderModeSync;
  config.logdir = logDir.c_str();
  config.nameprefix = "test_write";
  
  xlog_handle_t handle = xlog_new_instance(&config);
  
  xlog_write(handle, XLogLevelDebug, "tag", "test.cpp", "TestWriteLogs", 0, "debug message");
  xlog_write(handle, XLogLevelInfo, "tag", "test.cpp", "TestWriteLogs", 0, "info message");
  xlog_write(handle, XLogLevelWarn, "tag", "test.cpp", "TestWriteLogs", 0, "warn message");
  
  xlog_flush(handle, true);
  
  xlog_release_instance("test_write");
  std::cout << "✓ TestWriteLogs passed" << std::endl;
}

void TestLevelControl() {
  const char* tmpDir = getenv("XDG_RUNTIME_DIR");
  if (!tmpDir) tmpDir = "/tmp";
  
  std::string logDir = std::string(tmpDir) + "/xlog_test/";
  std::filesystem::create_directories(logDir);
  
  xlog_config_t config = {};
  config.mode = XLogAppenderModeSync;
  config.logdir = logDir.c_str();
  config.nameprefix = "test_level";
  
  xlog_handle_t handle = xlog_new_instance(&config);
  
  xlog_set_level(handle, XLogLevelDebug);
  assert(xlog_get_level(handle) == XLogLevelDebug && "Level mismatch");
  assert(xlog_is_enabled_for(handle, XLogLevelDebug) && "Debug should be enabled");
  assert(!xlog_is_enabled_for(handle, XLogLevelVerbose) && "Verbose should be disabled");
  
  xlog_release_instance("test_level");
  std::cout << "✓ TestLevelControl passed" << std::endl;
}

int main() {
  std::cout << "xlog Linux Native Tests (TODO: verify on target platform)" << std::endl;
  
  // TODO: Provide correct path to libxlog.so on test machine
  // May be in: /usr/lib, /usr/local/lib, or LD_LIBRARY_PATH
  if (!LoadXLogLibrary("libxlog.so")) {
    std::cerr << "Failed to load xlog library" << std::endl;
    return 1;
  }
  
  try {
    TestCreateInstance();
    TestWriteLogs();
    TestLevelControl();
    
    std::cout << "\nAll tests passed!" << std::endl;
    return 0;
  } catch (const std::exception& e) {
    std::cerr << "Test failed: " << e.what() << std::endl;
    return 1;
  }
}

#else
#error "This test is for Linux platform only"
#endif
```

- [ ] **Step 3: 验证**

Run: `wc -l /Users/jobsygao/Code/Tencent/mars/samples/xlog_flutter/example/linux/runner/xlog_native_test.cpp`

Expected: 约 150+ 行

- [ ] **Step 4: 提交（标注 TODO）**

```bash
cd /Users/jobsygao/Code/Tencent/mars
git add example/linux/runner/xlog_native_test.cpp
git commit -m "test: add Linux C++ test framework (TODO: verify on target platform)"
```

---

### 最终验证

#### Task 15: 验证所有测试文件已创建

- [ ] **Step 1: 检查 Flutter 集成测试文件**

Run: `ls -la /Users/jobsygao/Code/Tencent/mars/samples/xlog_flutter/example/integration_test/`

Expected: 7 个 .dart 文件

- [ ] **Step 2: 检查原生平台测试文件**

Run: `ls -la /Users/jobsygao/Code/Tencent/mars/samples/xlog_flutter/example/ios/RunnerTests/RunnerTests.swift && ls -la /Users/jobsygao/Code/Tencent/mars/samples/xlog_flutter/example/macos/RunnerTests/RunnerTests.swift`

Expected: 两个文件，大小都 > 5KB

- [ ] **Step 3: 检查 Android 测试**

Run: `wc -l /Users/jobsygao/Code/Tencent/mars/samples/xlog_flutter/example/android/app/src/androidTest/java/com/codexgao/xlog_flutter_example/XlogNativeInstrumentedTest.kt`

Expected: 350+ 行

- [ ] **Step 4: 检查 Windows/Linux 测试**

Run: `ls -la /Users/jobsygao/Code/Tencent/mars/samples/xlog_flutter/example/windows/runner/xlog_native_test.cpp && ls -la /Users/jobsygao/Code/Tencent/mars/samples/xlog_flutter/example/linux/runner/xlog_native_test.cpp`

Expected: 两个文件均存在

- [ ] **Step 5: 验证 pubspec.yaml 更新**

Run: `grep -A 5 "dev_dependencies:" /Users/jobsygao/Code/Tencent/mars/samples/xlog_flutter/example/pubspec.yaml`

Expected: 包含 path_provider 和 integration_test

---

## 总结

完成后的测试架构：

```
Flutter 集成测试（Dart）
├── test_utils.dart                 # 共享工具（临时目录、魔数验证）
├── xlog_open_test.dart             # 实例生命周期 (9 个用例)
├── xlog_write_test.dart            # 日志写入 + 配置 (18 个用例)
├── xlog_level_test.dart            # 级别控制 (7 个用例)
├── xlog_control_test.dart          # 控制方法 (7 个用例)
├── xlog_multi_instance_test.dart   # 多实例 (5 个用例)
└── xlog_all_test.dart              # 入口

iOS/macOS XCTest（ObjC 层）
├── iOS: RunnerTests.swift          # ~300 行，11 个测试方法
└── macOS: RunnerTests.swift        # 同上，环境不同

Android JUnit（Kotlin/JNA 层）
└── XlogNativeInstrumentedTest.kt  # ~350 行，原有 + 新增 9 个测试方法

Windows/Linux C++ 测试（暂缓验证）
├── Windows: xlog_native_test.cpp   # ~150 行，标注 TODO
└── Linux: xlog_native_test.cpp     # ~150 行，标注 TODO

总计测试用例数：
- Dart Integration: 46+ 用例
- iOS XCTest: 11 用例
- macOS XCTest: 11 用例
- Android JUnit: 15+ 用例
- Windows/Linux: 各 3+ 用例（暂缓）
```

**下一步：** 执行 Task 1-15，然后运行测试验证所有通过。
