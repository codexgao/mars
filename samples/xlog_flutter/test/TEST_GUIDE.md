# XLog Flutter 插件测试指南

本文档提供详细的测试运行和开发指导。

## 测试概述

xlog_flutter 插件包含以下测试套件：

### 1. 单元测试（Unit Tests）

#### xlog_flutter_test.dart
- **覆盖范围**：XLog 核心 API 功能测试
- **测试数量**：60+ 个测试用例
- **关键测试**：
  - 枚举类型验证（LogLevel、AppenderMode、CompressMode）
  - 日志方法签名验证
  - 参数有效性检查
  - 日志级别顺序关系
  - 路径和特殊字符处理

```bash
flutter test test/xlog_flutter_test.dart
```

#### xlog_config_test.dart
- **覆盖范围**：XLogConfig 配置类详细测试
- **测试数量**：80+ 个测试用例
- **关键测试**：
  - 配置对象不可变性
  - 字段验证
  - 边界情况处理
  - 组合配置验证
  - 类型安全检查

```bash
flutter test test/xlog_config_test.dart
```

#### xlog_bindings_test.dart
- **覆盖范围**：FFI 绑定层测试
- **测试数量**：70+ 个测试用例
- **关键测试**：
  - 库加载验证
  - 函数签名检查
  - 参数转换测试
  - 内存管理验证
  - UTF-8 编码验证
  - 平台兼容性检查

```bash
flutter test test/xlog_bindings_test.dart
```

### 2. 集成测试（Integration Tests）

#### xlog_integration_test.dart
- **覆盖范围**：完整的端到端功能测试
- **测试数量**：50+ 个测试用例
- **关键测试**：
  - 初始化流程
  - 日志写入和过滤
  - 文件操作和轮转
  - 配置变更
  - 错误处理
  - 性能基准测试

```bash
flutter test test/integration_tests/xlog_integration_test.dart
```

### 3. 模拟库（Mocks）

#### mocks/xlog_flutter_mock.dart
- 提供测试辅助类和模拟对象
- 包含配置验证器、日志缓冲区、文件系统模拟等
- 支持测试数据生成

## 运行测试

### 运行所有测试

```bash
cd samples/xlog_flutter

# 获取依赖
flutter pub get

# 运行所有测试
flutter test

# 运行所有测试并生成覆盖率报告
flutter test --coverage
```

### 运行特定测试文件

```bash
# 单独运行某个测试文件
flutter test test/xlog_flutter_test.dart
flutter test test/xlog_config_test.dart
flutter test test/xlog_bindings_test.dart
flutter test test/integration_tests/xlog_integration_test.dart
```

### 运行特定测试组

```bash
# 运行特定的测试组
flutter test test/xlog_flutter_test.dart -k "枚举类型测试"
flutter test test/xlog_config_test.dart -k "不可变性"
flutter test test/integration_tests/xlog_integration_test.dart -k "性能"
```

### 运行特定单个测试

```bash
# 运行单个测试用例
flutter test test/xlog_flutter_test.dart -k "LogLevel 枚举包含所有日志级别"
```

### 详细输出

```bash
# 显示详细的测试输出
flutter test --verbose

# 显示非常详细的输出
flutter test -vv
```

## 测试覆盖率

### 生成覆盖率报告

```bash
# 生成覆盖率数据
flutter test --coverage

# 使用 lcov 生成 HTML 报告（需要安装 lcov）
# macOS/Linux
lcov --list coverage/lcov.info
genhtml coverage/lcov.info -o coverage/

# Windows
# 使用 gcovr 或其他工具
```

### 查看覆盖率

```bash
# 打开生成的 HTML 报告
open coverage/index.html  # macOS
xdg-open coverage/index.html  # Linux
start coverage/index.html  # Windows
```

## 测试用例详解

### 单元测试组织结构

```
xlog_flutter_test.dart
├── 枚举类型测试
│   ├── LogLevel 枚举验证
│   ├── AppenderMode 枚举验证
│   └── CompressMode 枚举验证
├── 配置类测试
│   ├── 必需参数创建
│   ├── 所有字段验证
│   └── 默认值检查
├── 静态方法测试
│   ├── open/close 方法
│   ├── 日志写入方法
│   └── 配置方法
├── 日志参数验证
│   ├── 空字符串处理
│   ├── Unicode 支持
│   ├── 长字符串处理
│   └── 特殊字符处理
└── 日志级别测试
    ├── 级别顺序验证
    ├── 级别过滤逻辑
    └── 级别值范围
```

### 集成测试场景

```
xlog_integration_test.dart
├── 初始化流程
│   ├── 完整初始化
│   ├── 配置验证
│   └── 参数边界值
├── 日志写入
│   ├── 各级别日志
│   ├── 标签过滤
│   ├── 长消息处理
│   └── Unicode 支持
├── 文件操作
│   ├── 文件创建和写入
│   ├── 文件轮转
│   ├── 大小限制
│   └── 清理策略
├── 配置变更
│   ├── 运行时级别变更
│   ├── 输出模式切换
│   └── 大小限制更新
├── 错误处理
│   ├── 无效配置检测
│   ├── 权限问题
│   ├── 磁盘满处理
│   └── 并发冲突
└── 性能测试
    ├── 大量写入性能
    ├── 查询性能
    └── 内存使用
```

## 模拟对象使用示例

### 测试日志写入

```dart
import 'package:xlog_flutter/xlog_flutter.dart';
import 'mocks/xlog_flutter_mock.dart';

void main() {
  test('日志写入测试', () {
    final buffer = MockLogBuffer();
    
    buffer.write(1, 'my_tag', 'Test message');
    
    expect(buffer.getEntryCount(), 1);
    expect(buffer.getEntriesByTag('my_tag').length, 1);
  });
}
```

### 测试配置验证

```dart
test('配置验证', () {
  final config = MockConfigBuilder()
      .withLogDir('/logs')
      .withNamePrefix('app')
      .withLevel(1)
      .build();
  
  expect(ConfigValidator.isConfigValid(config), true);
});
```

### 测试文件操作

```dart
test('文件操作', () {
  final fs = MockFileSystem();
  fs.createFile('./logs/app.log', 'Initial content');
  
  expect(fs.fileExists('./logs/app.log'), true);
  expect(fs.getTotalSize(), 15);
});
```

## 常见问题

### 问：如何在没有原生库的情况下运行测试？

答：大部分单元测试不需要真实的原生库，因为它们只测试 Dart 层的 API。对于需要 FFI 调用的集成测试，测试框架会自动处理缺失的库。

### 问：如何调试测试？

答：
```bash
# 在调试器中运行测试
flutter test --debug-all

# 或使用 IDE 的调试功能
# 在 Android Studio/IntelliJ 中：右键单击测试文件 > Run 'xxx' with Coverage
# 或点击测试旁边的绿色三角形
```

### 问：如何跳过某些测试？

答：
```dart
// 使用 skip: true 跳过单个测试
test('跳过的测试', () {
  // ...
}, skip: true);

// 或使用 skip 参数指定原因
test('跳过的测试', () {
  // ...
}, skip: 'Not implemented yet');
```

### 问：如何只运行快速测试？

答：
```bash
# 给测试添加标签
@FastTest()
test('快速测试', () {
  // ...
});

# 只运行标记为快速的测试
flutter test --tags fast
```

## 测试最佳实践

### 1. 使用描述性的测试名称

```dart
// 好的
test('当 logDir 为空时，配置验证应该失败', () {
  // ...
});

// 不好
test('测试配置', () {
  // ...
});
```

### 2. 使用 setUp 和 tearDown

```dart
setUp(() {
  // 在每个测试之前运行
  fixture = TestFixture();
  fixture.setUp();
});

tearDown(() {
  // 在每个测试之后运行
  fixture.tearDown();
});
```

### 3. 测试应该独立

```dart
// 好的
test('日志写入', () {
  final buffer = MockLogBuffer();
  buffer.write(1, 'tag', 'message');
  expect(buffer.getEntryCount(), 1);
});

// 不好
late MockLogBuffer buffer; // 全局变量

test('日志写入 1', () {
  buffer.write(1, 'tag', 'message');
});

test('日志写入 2', () {
  // 依赖于上一个测试的状态
});
```

### 4. 使用合理的断言

```dart
// 好的
expect(value, isNotNull);
expect(value, isA<String>());
expect(value.length, greaterThan(0));

// 不好
expect(value != null, true);
expect(value.length > 0, true);
```

## 持续集成（CI）

### GitHub Actions 示例

```yaml
name: Test

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    
    steps:
      - uses: actions/checkout@v3
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: 'stable'
      
      - name: Get dependencies
        run: flutter pub get
      
      - name: Run tests
        run: flutter test
      
      - name: Generate coverage
        run: flutter test --coverage
      
      - name: Upload coverage
        uses: codecov/codecov-action@v3
```

## 性能测试

### 运行性能基准测试

```bash
# 性能测试通常较慢
flutter test test/integration_tests/xlog_integration_test.dart -k "性能"
```

### 分析性能结果

```dart
test('日志写入吞吐量', () {
  const count = 10000;
  final stopwatch = Stopwatch()..start();
  
  for (int i = 0; i < count; i++) {
    logBuffer.write(1, 'tag', 'message');
  }
  
  stopwatch.stop();
  final throughput = count / (stopwatch.elapsedMilliseconds / 1000);
  
  print('吞吐量：$throughput 条/秒');
  expect(throughput, greaterThan(1000));
});
```

## 故障排除

### 测试超时

如果测试超时：

```dart
test('可能很慢的测试', () async {
  // ...
}, timeout: Timeout(Duration(seconds: 30)));
```

### 内存泄漏检测

```bash
# 使用 valgrind (Linux)
valgrind --leak-check=full flutter test

# 使用 Instruments (macOS)
# 在 Xcode 中打开生成的应用并使用 Instruments
```

### 测试隔离问题

```bash
# 禁用并行测试运行
flutter test --concurrency=1
```

## 进一步阅读

- [Flutter 测试官方文档](https://flutter.dev/docs/testing)
- [Mockito 文档](https://pub.dev/packages/mockito)
- [FFI 测试最佳实践](https://github.com/dart-lang/ffigen)
