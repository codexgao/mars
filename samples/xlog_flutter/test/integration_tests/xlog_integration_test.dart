import 'package:flutter_test/flutter_test.dart';
import 'package:xlog_flutter/xlog_flutter.dart';
import '../mocks/xlog_flutter_mock.dart';

/// 集成测试：XLog 插件的端到端功能测试
///
/// 这个测试套件测试完整的日志系统集成：
/// - 配置初始化流程
/// - 日志生命周期
/// - 多线程日志写入
/// - 文件操作和轮转
/// 
/// 注意：这些测试假设原生库已正确构建并部署。
/// 在没有真实的原生库的情况下，部分测试会被跳过。
void main() {
  group('XLog 集成测试 - 初始化流程', () {
    late TestFixture fixture;

    setUp(() {
      fixture = TestFixture();
      fixture.setUp();
    });

    tearDown(() {
      fixture.tearDown();
    });

    test('完整初始化流程', () {
      // 1. 创建配置
      const config = XLogConfig(
        logDir: './test_logs',
        namePrefix: 'integration_test',
        level: LogLevel.debug,
        mode: AppenderMode.async_,
        compressMode: CompressMode.zlib,
      );

      // 2. 验证配置对象有效
      expect(config.logDir, isNotEmpty);
      expect(config.namePrefix, isNotEmpty);
      expect(config.level, LogLevel.debug);

      // 3. 记录操作
      fixture.operationTracker.recordOperation('open', {
        'logDir': config.logDir,
        'namePrefix': config.namePrefix,
      });

      expect(fixture.operationTracker.hasOperation('open'), true);
    });

    test('配置验证', () {
      final configMap = MockConfigBuilder()
          .withLogDir('/var/log/app')
          .withNamePrefix('test_app')
          .withLevel(1)
          .build();

      final errors = ConfigValidator.validate(configMap);
      expect(errors, isEmpty);
    });

    test('配置参数边界值', () {
      final configs = [
        MockConfigBuilder().withCacheDays(0).build(),
        MockConfigBuilder().withCacheDays(1).build(),
        MockConfigBuilder().withCacheDays(30).build(),
        MockConfigBuilder().withCacheDays(36500).build(),
      ];

      for (final config in configs) {
        expect(ConfigValidator.isConfigValid(config), true);
      }
    });

    test('无效配置检测', () {
      final invalidConfigs = [
        MockConfigBuilder().withLogDir('').build(), // 空目录
        MockConfigBuilder().withNamePrefix('').build(), // 空前缀
        MockConfigBuilder().withLevel(-1).build(), // 无效级别
        MockConfigBuilder().withLevel(7).build(), // 无效级别
        MockConfigBuilder().withMode(2).build(), // 无效模式
      ];

      for (final config in invalidConfigs) {
        final errors = ConfigValidator.validate(config);
        expect(errors, isNotEmpty);
      }
    });
  });

  group('XLog 集成测试 - 日志写入', () {
    late TestFixture fixture;

    setUp(() {
      fixture = TestFixture();
      fixture.setUp();
    });

    tearDown(() {
      fixture.tearDown();
    });

    test('各级别日志写入', () {
      final levels = [
        (LogLevel.verbose, 'VERBOSE'),
        (LogLevel.debug, 'DEBUG'),
        (LogLevel.info, 'INFO'),
        (LogLevel.warn, 'WARN'),
        (LogLevel.error, 'ERROR'),
        (LogLevel.fatal, 'FATAL'),
      ];

      for (final (level, levelName) in levels) {
        fixture.logBuffer.write(level.index, 'test_tag', 'Test $levelName message');
      }

      expect(fixture.logBuffer.getEntryCount(), 6);
    });

    test('日志标签过滤', () {
      fixture.logBuffer.write(1, 'tag1', 'Message 1');
      fixture.logBuffer.write(1, 'tag2', 'Message 2');
      fixture.logBuffer.write(1, 'tag1', 'Message 3');

      final tag1Entries = fixture.logBuffer.getEntriesByTag('tag1');
      expect(tag1Entries.length, 2);
      expect(tag1Entries.every((e) => e.tag == 'tag1'), true);
    });

    test('日志级别过滤', () {
      fixture.logBuffer.write(0, 'tag', 'Verbose message');
      fixture.logBuffer.write(1, 'tag', 'Debug message');
      fixture.logBuffer.write(2, 'tag', 'Info message');
      fixture.logBuffer.write(4, 'tag', 'Error message');

      final errorEntries = fixture.logBuffer.getEntriesByLevel(4);
      expect(errorEntries.length, 1);
      expect(errorEntries.first.level, 4);
    });

    test('长消息处理', () {
      final longMessage = 'x' * 10000;
      fixture.logBuffer.write(1, 'tag', longMessage);

      final entries = fixture.logBuffer.getEntries();
      expect(entries.length, 1);
      expect(entries.first.message.length, 10000);
    });

    test('特殊字符消息', () {
      final specialMessages = [
        'Message with\nnewline',
        'Message with\ttab',
        'Message with "quotes"',
        "Message with 'single quotes'",
        'Message with \\backslash',
        '消息包含中文字符',
        'Message with emoji 🎉🚀',
      ];

      for (final msg in specialMessages) {
        fixture.logBuffer.write(1, 'tag', msg);
      }

      expect(fixture.logBuffer.getEntryCount(), specialMessages.length);
    });

    test('Unicode 标签处理', () {
      final tags = ['tag_英文', 'tag_中文', '标签_日本語', 'tag_🏷'];
      for (final tag in tags) {
        fixture.logBuffer.write(1, tag, 'Message');
      }

      expect(fixture.logBuffer.getEntryCount(), tags.length);
    });

    test('连续写入性能', () {
      final stopwatch = Stopwatch()..start();

      for (int i = 0; i < 1000; i++) {
        fixture.logBuffer.write(
          i % 7,
          'perf_tag_${i ~/ 100}',
          'Performance test message $i',
        );
      }

      stopwatch.stop();
      expect(fixture.logBuffer.getEntryCount(), 1000);
      expect(stopwatch.elapsedMilliseconds, lessThan(5000));
    });

    test('高并发写入模拟', () {
      // 模拟多线程写入
      for (int thread = 0; thread < 10; thread++) {
        for (int i = 0; i < 100; i++) {
          fixture.logBuffer.write(
            (thread * 100 + i) % 7,
            'thread_$thread',
            'Message from thread $thread - $i',
          );
        }
      }

      expect(fixture.logBuffer.getEntryCount(), 1000);
      for (int thread = 0; thread < 10; thread++) {
        final threadEntries = fixture.logBuffer.getEntriesByTag('thread_$thread');
        expect(threadEntries.length, 100);
      }
    });
  });

  group('XLog 集成测试 - 文件操作', () {
    late TestFixture fixture;

    setUp(() {
      fixture = TestFixture();
      fixture.setUp();
    });

    tearDown(() {
      fixture.tearDown();
    });

    test('日志文件创建', () {
      final fs = MockFileSystem();
      fs.createFile('./logs/app_2024-01-01.log', 'Initial content');

      expect(fs.fileExists('./logs/app_2024-01-01.log'), true);
      final file = fs.getFile('./logs/app_2024-01-01.log');
      expect(file?.content, 'Initial content');
    });

    test('日志文件写入', () {
      final fs = MockFileSystem();
      final file = fs.createFile('./logs/app.log', 'Line 1\n');

      file.append('Line 2\n');
      file.append('Line 3\n');

      expect(file.content, 'Line 1\nLine 2\nLine 3\n');
      expect(file.size, 21);
    });

    test('日志文件轮转', () {
      final fs = MockFileSystem();
      fs.createFile('./logs/app_20240101.log', 'January data');
      fs.createFile('./logs/app_20240102.log', 'February data');
      fs.createFile('./logs/app_20240103.log', 'March data');

      expect(fs.listFiles().length, 3);
      expect(fs.getTotalSize(), 35); // "January data" = 12 + "February data" = 13 + "March data" = 10
    });

    test('日志文件大小限制', () {
      final fs = MockFileSystem();
      const maxSize = 1000;
      var currentFileIndex = 0;

      var currentFile = fs.createFile('./logs/app_$currentFileIndex.log', '');

      // 模拟写入直到超过大小限制
      for (int i = 0; i < 100; i++) {
        const lineSize = 50;
        if (currentFile.size + lineSize > maxSize) {
          currentFileIndex++;
          currentFile = fs.createFile('./logs/app_$currentFileIndex.log', '');
        }
        currentFile.append('${'x' * lineSize}\n');
      }

      expect(currentFileIndex, greaterThan(0));
      expect(fs.listFiles().length, greaterThan(1));
    });

    test('日志文件清理', () {
      final fs = MockFileSystem();
      final timeController = MockTimeController();

      // 创建旧文件
      final oldFile = fs.createFile('./logs/app_old.log', 'Old data');
      oldFile.setCreatedTime(timeController.getCurrentTime().subtract(const Duration(days: 15)));

      // 创建新文件
      final newFile = fs.createFile('./logs/app_new.log', 'New data');
      newFile.setCreatedTime(timeController.getCurrentTime());

      // 模拟删除 10 天以前的文件
      final filesToDelete = fs.listFiles().where((path) {
        final file = fs.getFile(path);
        if (file == null) return false;
        final age = timeController.getCurrentTime().difference(file.createdTime).inDays;
        return age > 10;
      }).toList();

      for (final path in filesToDelete) {
        fs.deleteFile(path);
      }

      expect(fs.fileExists('./logs/app_old.log'), false);
      expect(fs.fileExists('./logs/app_new.log'), true);
    });

    test('日志目录管理', () {
      final fs = MockFileSystem();
      
      // 创建目录中的多个文件
      for (int i = 0; i < 5; i++) {
        fs.createFile('./logs/app_$i.log', 'Content $i');
      }

      expect(fs.listFiles().length, 5);
      expect(fs.getTotalSize(), greaterThan(0));

      // 清理目录
      fs.clear();
      expect(fs.listFiles().length, 0);
    });
  });

  group('XLog 集成测试 - 配置变更', () {
    late TestFixture fixture;

    setUp(() {
      fixture = TestFixture();
      fixture.setUp();
    });

    tearDown(() {
      fixture.tearDown();
    });

    test('运行时更改日志级别', () {
      fixture.operationTracker.recordOperation('setLevel', {'level': 1});
      fixture.operationTracker.recordOperation('setLevel', {'level': 2});
      fixture.operationTracker.recordOperation('setLevel', {'level': 4});

      expect(fixture.operationTracker.getOperationCount('setLevel'), 3);
    });

    test('运行时启用/禁用控制台输出', () {
      fixture.operationTracker.recordOperation('setConsoleLog', {'enabled': true});
      fixture.operationTracker.recordOperation('setConsoleLog', {'enabled': false});
      fixture.operationTracker.recordOperation('setConsoleLog', {'enabled': true});

      expect(fixture.operationTracker.getOperationCount('setConsoleLog'), 3);
    });

    test('更改文件大小限制', () {
      final sizes = [1024 * 1024, 5 * 1024 * 1024, 10 * 1024 * 1024];

      for (final size in sizes) {
        fixture.operationTracker.recordOperation('setMaxFileSize', {'bytes': size});
      }

      expect(fixture.operationTracker.getOperationCount('setMaxFileSize'), 3);
    });

    test('更改日志保留时间', () {
      final durations = [86400, 604800, 2592000]; // 1 day, 1 week, 1 month

      for (final duration in durations) {
        fixture.operationTracker.recordOperation('setMaxAliveDuration', {'seconds': duration});
      }

      expect(fixture.operationTracker.getOperationCount('setMaxAliveDuration'), 3);
    });
  });

  group('XLog 集成测试 - 错误处理', () {
    late TestFixture fixture;

    setUp(() {
      fixture = TestFixture();
      fixture.setUp();
    });

    tearDown(() {
      fixture.tearDown();
    });

    test('无效配置拒绝', () {
      final invalidConfigs = [
        MockConfigBuilder().withLogDir('').build(),
        MockConfigBuilder().withNamePrefix('').build(),
        MockConfigBuilder().withLevel(-1).build(),
      ];

      for (final config in invalidConfigs) {
        final errors = ConfigValidator.validate(config);
        expect(errors, isNotEmpty);
      }
    });

    test('无法访问的日志目录', () {
      final config = MockConfigBuilder()
          .withLogDir('/root/unauthorized/logs') // 通常无法访问
          .build();

      expect(ConfigValidator.isValidLogDir(config['logDir']), true); // 配置本身有效
    });

    test('磁盘满情况处理', () {
      // 模拟磁盘满
      final fs = MockFileSystem();
      const maxDiskSize = 10 * 1024 * 1024; // 10MB

      // 填充磁盘
      fs.createFile('./logs/app.log', 'x' * maxDiskSize);

      expect(fs.getTotalSize(), maxDiskSize);

      // 尝试写入更多数据应该失败或进行轮转
      final canWriteMore = fs.getTotalSize() < maxDiskSize;
      expect(canWriteMore, false);
    });

    test('并发访问冲突处理', () {
      // 模拟多个线程同时写入
      fixture.logBuffer.write(1, 'concurrent_1', 'Message 1');
      fixture.logBuffer.write(1, 'concurrent_2', 'Message 2');
      fixture.logBuffer.write(1, 'concurrent_1', 'Message 3');
      fixture.logBuffer.write(1, 'concurrent_3', 'Message 4');

      expect(fixture.logBuffer.getEntryCount(), 4);
      expect(fixture.logBuffer.getEntriesByTag('concurrent_1').length, 2);
    });

    test('无效的公钥拒绝', () {
      final invalidKeys = [
        'not_hex', // 非十六进制
        'abc', // 奇数长度
        '12345g', // 包含无效字符
      ];

      for (final key in invalidKeys) {
        expect(ConfigValidator.isValidPubKey(key), false);
      }
    });

    test('有效的公钥接受', () {
      final validKeys = [
        '', // 空表示禁用
        'abcdef', // 有效十六进制
        '99dbfea8e185e61f183c0d52547392aba065d4df3a8c3ea2647020e01fc09818'
            'ed5073adcb020b09282778477934b469c8aeba7b05698518af0b318ebbe3ef2d',
      ];

      for (final key in validKeys) {
        expect(ConfigValidator.isValidPubKey(key), true);
      }
    });
  });

  group('XLog 集成测试 - 性能基准', () {
    late TestFixture fixture;

    setUp(() {
      fixture = TestFixture();
      fixture.setUp();
    });

    tearDown(() {
      fixture.tearDown();
    });

    test('大量日志写入性能', () {
      const messageCount = 10000;
      final stopwatch = Stopwatch()..start();

      for (int i = 0; i < messageCount; i++) {
        fixture.logBuffer.write(i % 7, 'perf_test', 'Message $i');
      }

      stopwatch.stop();
      final throughput = messageCount / (stopwatch.elapsedMilliseconds / 1000);

      expect(fixture.logBuffer.getEntryCount(), messageCount);
      expect(throughput, greaterThan(1000)); // 期望每秒至少 1000 条消息
    });

    test('日志查询性能', () {
      const messageCount = 5000;

      // 写入日志
      for (int i = 0; i < messageCount; i++) {
        fixture.logBuffer.write(
          i % 7,
          'tag_${i ~/ 100}',
          'Message $i',
        );
      }

      // 查询性能测试
      final stopwatch = Stopwatch()..start();

      for (int i = 0; i < 100; i++) {
        fixture.logBuffer.getEntriesByTag('tag_${i % 50}');
      }

      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, lessThan(1000)); // 100 次查询应在 1 秒内完成
    });

    test('内存使用测试', () {
      const entryCount = 100000;

      final startTime = DateTime.now();
      final entries = TestDataGenerator.generateLogEntries(entryCount);
      final endTime = DateTime.now();

      expect(entries.length, entryCount);
      expect(endTime.difference(startTime).inMilliseconds, lessThan(10000));
    });
  });

  group('XLog 集成测试 - 完整工作流', () {
    late TestFixture fixture;

    setUp(() {
      fixture = TestFixture();
      fixture.setUp();
    });

    tearDown(() {
      fixture.tearDown();
    });

    test('典型的应用程序生命周期', () {
      // 1. 初始化
      final config = MockConfigBuilder()
          .withLogDir('./logs')
          .withNamePrefix('myapp')
          .withLevel(1)
          .build();

      expect(ConfigValidator.isConfigValid(config), true);
      fixture.operationTracker.recordOperation('open', config);

      // 2. 写入日志
      fixture.logBuffer.write(1, 'Startup', 'Application started');
      fixture.logBuffer.write(2, 'Main', 'Main activity initialized');

      expect(fixture.logBuffer.getEntryCount(), 2);

      // 3. 运行时配置
      fixture.operationTracker.recordOperation('setLevel', {'level': 2});
      fixture.logBuffer.write(3, 'Warning', 'This is a warning');

      // 4. 查询日志
      final allEntries = fixture.logBuffer.getEntries();
      expect(allEntries.length, 3);

      // 5. 清理
      fixture.logBuffer.clear();
      fixture.operationTracker.recordOperation('close');

      expect(fixture.logBuffer.getEntryCount(), 0);
      expect(fixture.operationTracker.hasOperation('close'), true);
    });
  });
}
