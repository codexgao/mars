# XLog Flutter 测试套件

本目录包含 xlog_flutter 插件的完整测试套件。

## 目录结构

```
test/
├── README.md                                # 本文件
├── TEST_GUIDE.md                            # 详细的测试指南
├── xlog_flutter_test.dart                   # 核心 API 单元测试（60+ 用例）
├── xlog_config_test.dart                    # 配置类单元测试（80+ 用例）
├── xlog_bindings_test.dart                  # FFI 绑定单元测试（70+ 用例）
├── mocks/
│   └── xlog_flutter_mock.dart              # 模拟对象和辅助类
└── integration_tests/
    └── xlog_integration_test.dart           # 集成测试（50+ 用例）
```

## 快速开始

### 运行所有测试

```bash
cd samples/xlog_flutter
flutter pub get
flutter test
```

### 运行特定测试文件

```bash
# 运行单元测试
flutter test test/xlog_flutter_test.dart
flutter test test/xlog_config_test.dart
flutter test test/xlog_bindings_test.dart

# 运行集成测试
flutter test test/integration_tests/xlog_integration_test.dart
```

### 查看测试覆盖率

```bash
flutter test --coverage
```

## 测试套件概览

### xlog_flutter_test.dart
**60+ 个测试用例，覆盖 XLog 核心 API**

- ✅ 枚举类型验证（LogLevel、AppenderMode、CompressMode）
- ✅ 日志方法签名和参数
- ✅ 日志级别顺序关系
- ✅ 特殊字符和 Unicode 处理
- ✅ 源代码位置信息（文件名、函数名、行号）
- ✅ 运行时配置方法

### xlog_config_test.dart
**80+ 个测试用例，专注配置验证**

- ✅ XLogConfig 类的完整字段验证
- ✅ 不可变性检查
- ✅ 默认值验证
- ✅ 边界值测试
- ✅ 路径和前缀格式验证
- ✅ 公钥和缓存配置
- ✅ 类型安全检查

### xlog_bindings_test.dart
**70+ 个测试用例，FFI 层验证**

- ✅ 库加载和平台兼容性
- ✅ 函数签名检查
- ✅ 参数转换（字符串、整数、枚举）
- ✅ 内存管理（malloc/free）
- ✅ UTF-8 编码验证
- ✅ 跨语言数据类型处理
- ✅ 平台特定库名称

### xlog_integration_test.dart
**50+ 个测试用例，端到端功能**

- ✅ 初始化流程和配置验证
- ✅ 日志写入、过滤和查询
- ✅ 文件操作和轮转
- ✅ 配置变更和运行时更新
- ✅ 错误处理和异常情况
- ✅ 性能基准测试
- ✅ 完整应用生命周期模拟

### mocks/xlog_flutter_mock.dart
**测试支持库和模拟对象**

- `MockLogBuffer` - 日志缓冲区模拟
- `MockFileSystem` - 文件系统模拟
- `NativeOperationTracker` - 原生调用追踪
- `ConfigValidator` - 配置验证工具
- `MockConfigBuilder` - 配置构建器
- `TestFixture` - 测试夹具
- `TestDataGenerator` - 测试数据生成

## 测试统计

| 文件 | 测试用例数 | 覆盖范围 |
|------|-----------|--------|
| xlog_flutter_test.dart | 60+ | 核心 API |
| xlog_config_test.dart | 80+ | 配置验证 |
| xlog_bindings_test.dart | 70+ | FFI 绑定 |
| xlog_integration_test.dart | 50+ | 集成功能 |
| **总计** | **260+** | **完整功能** |

## 关键测试场景

### 1. 初始化和生命周期
- [x] 配置创建和验证
- [x] 日志系统初始化
- [x] 运行时状态管理
- [x] 正确关闭和清理

### 2. 日志写入
- [x] 所有日志级别（verbose、debug、info、warn、error、fatal）
- [x] 标签和消息处理
- [x] 源代码位置信息
- [x] 长字符串和特殊字符
- [x] Unicode 和多字节字符
- [x] 并发写入

### 3. 配置和运行时设置
- [x] 编码器模式（异步/同步）
- [x] 压缩方式（zlib/zstd）
- [x] 日志级别过滤
- [x] 文件大小限制
- [x] 保留期限设置

### 4. 文件管理
- [x] 日志文件创建
- [x] 文件轮转
- [x] 大小限制执行
- [x] 过期文件清理
- [x] 目录管理

### 5. 错误处理
- [x] 无效配置检测
- [x] 权限问题模拟
- [x] 磁盘空间不足
- [x] 并发冲突

### 6. 性能
- [x] 写入吞吐量基准
- [x] 查询性能
- [x] 内存使用
- [x] 长期稳定性

## 运行特定测试的示例

```bash
# 只运行配置验证测试
flutter test test/xlog_config_test.dart -k "字段验证"

# 只运行性能测试
flutter test test/integration_tests/xlog_integration_test.dart -k "性能"

# 运行某个特定测试
flutter test test/xlog_flutter_test.dart -k "LogLevel 枚举"

# 显示详细输出
flutter test --verbose test/xlog_flutter_test.dart

# 并发运行所有测试
flutter test --concurrency=4
```

## 编写新测试

### 基本模板

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:xlog_flutter/xlog_flutter.dart';
import 'mocks/xlog_flutter_mock.dart';

void main() {
  group('新测试套件', () {
    late TestFixture fixture;

    setUp(() {
      fixture = TestFixture();
      fixture.setUp();
    });

    tearDown(() {
      fixture.tearDown();
    });

    test('测试描述', () {
      // 准备
      final config = XLogConfig(logDir: '/logs', namePrefix: 'test');

      // 执行
      expect(config.logDir, '/logs');

      // 验证
      expect(config.namePrefix, 'test');
    });
  });
}
```

### 使用模拟对象

```dart
test('使用日志缓冲区', () {
  final buffer = MockLogBuffer();
  
  buffer.write(1, 'tag', 'message');
  
  expect(buffer.getEntryCount(), 1);
  expect(buffer.getEntriesByTag('tag').length, 1);
});

test('使用配置构建器', () {
  final config = MockConfigBuilder()
      .withLogDir('/logs')
      .withNamePrefix('app')
      .withLevel(2)
      .build();
  
  expect(ConfigValidator.isConfigValid(config), true);
});
```

## 故障排除

### 测试失败排查

1. **检查依赖版本**
   ```bash
   flutter pub outdated
   flutter pub upgrade
   ```

2. **清理缓存**
   ```bash
   flutter clean
   flutter pub get
   flutter test
   ```

3. **查看详细输出**
   ```bash
   flutter test --verbose
   ```

4. **在调试器中运行**
   - 在 IDE 中右键单击测试文件
   - 选择 "Run 'xxx' in Debugger"

### 常见问题

**Q: 测试超时？**
A: 增加超时时间：
```dart
test('slow test', () { ... }, timeout: Timeout(Duration(seconds: 30)));
```

**Q: 内存问题？**
A: 降低并发数：
```bash
flutter test --concurrency=1
```

**Q: FFI 相关错误？**
A: 这些错误在没有原生库的环境中是预期的。集成测试会跳过真实的 FFI 调用。

## 最佳实践

1. **编写清晰的测试名称** - 测试名应该描述它测试的内容
2. **使用 setUp/tearDown** - 确保测试隔离和清理
3. **避免测试间依赖** - 每个测试应该独立运行
4. **测试边界情况** - 空字符串、极限值、无效输入
5. **使用 AAA 模式** - Arrange（准备）、Act（执行）、Assert（验证）

## 后续文档

详见 [TEST_GUIDE.md](TEST_GUIDE.md) 了解更详细的测试指导。

## 许可证

这些测试遵循与 mars 项目相同的许可证。
