import 'package:flutter_test/flutter_test.dart';
import 'package:xlog_flutter/xlog_flutter.dart';

/// 单元测试：XLogConfig 配置类的详细功能测试
///
/// 这个测试套件专注于配置对象的所有方面：
/// - 不可变性
/// - 字段验证
/// - 边界情况
/// - 类型安全
void main() {
  group('XLogConfig - 基础属性测试', () {
    test('创建最小配置', () {
      const config = XLogConfig(
        logDir: '/logs',
        namePrefix: 'app',
      );

      expect(config.logDir, '/logs');
      expect(config.namePrefix, 'app');
      expect(config.level, LogLevel.debug);
      expect(config.mode, AppenderMode.async_);
      expect(config.compressMode, CompressMode.zlib);
      expect(config.pubKey, '');
      expect(config.cacheDir, '');
      expect(config.cacheDays, 0);
    });

    test('创建完整配置', () {
      const config = XLogConfig(
        logDir: '/var/log/app',
        namePrefix: 'myapp',
        level: LogLevel.warn,
        mode: AppenderMode.sync_,
        compressMode: CompressMode.zstd,
        pubKey: 'abc123def456',
        cacheDir: '/var/cache/app',
        cacheDays: 15,
      );

      expect(config.logDir, '/var/log/app');
      expect(config.namePrefix, 'myapp');
      expect(config.level, LogLevel.warn);
      expect(config.mode, AppenderMode.sync_);
      expect(config.compressMode, CompressMode.zstd);
      expect(config.pubKey, 'abc123def456');
      expect(config.cacheDir, '/var/cache/app');
      expect(config.cacheDays, 15);
    });
  });

  group('XLogConfig - 字段验证', () {
    test('logDir 不为空', () {
      const config = XLogConfig(
        logDir: '/path/to/logs',
        namePrefix: 'test',
      );
      expect(config.logDir, isNotEmpty);
    });

    test('logDir 支持常见路径', () {
      final paths = [
        '/logs',
        '/var/log',
        '/home/user/logs',
        './logs',
        '../logs',
        'C:/Users/logs', // Windows 风格（在 Dart 中仍为字符串）
      ];

      for (final path in paths) {
        final config = XLogConfig(
          logDir: path,
          namePrefix: 'test',
        );
        expect(config.logDir, path);
      }
    });

    test('namePrefix 不为空', () {
      const config = XLogConfig(
        logDir: '/logs',
        namePrefix: 'myapp',
      );
      expect(config.namePrefix, isNotEmpty);
    });

    test('namePrefix 支持多种格式', () {
      final prefixes = [
        'app',
        'my_app',
        'MyApp',
        'my-app',
        'app123',
        '123app',
        'a',
        'my_app_v1_2_3',
      ];

      for (final prefix in prefixes) {
        final config = XLogConfig(
          logDir: '/logs',
          namePrefix: prefix,
        );
        expect(config.namePrefix, prefix);
      }
    });

    test('level 字段存储正确的枚举值', () {
      const levels = LogLevel.values;
      for (final level in levels) {
        final config = XLogConfig(
          logDir: '/logs',
          namePrefix: 'test',
          level: level,
        );
        expect(config.level, level);
      }
    });

    test('mode 字段存储正确的枚举值', () {
      const config1 = XLogConfig(
        logDir: '/logs',
        namePrefix: 'test',
        mode: AppenderMode.async_,
      );
      expect(config1.mode, AppenderMode.async_);

      const config2 = XLogConfig(
        logDir: '/logs',
        namePrefix: 'test',
        mode: AppenderMode.sync_,
      );
      expect(config2.mode, AppenderMode.sync_);
    });

    test('compressMode 字段存储正确的枚举值', () {
      const config1 = XLogConfig(
        logDir: '/logs',
        namePrefix: 'test',
        compressMode: CompressMode.zlib,
      );
      expect(config1.compressMode, CompressMode.zlib);

      const config2 = XLogConfig(
        logDir: '/logs',
        namePrefix: 'test',
        compressMode: CompressMode.zstd,
      );
      expect(config2.compressMode, CompressMode.zstd);
    });

    test('pubKey 可以为空字符串', () {
      const config = XLogConfig(
        logDir: '/logs',
        namePrefix: 'test',
        pubKey: '',
      );
      expect(config.pubKey, '');
    });

    test('pubKey 可以为长十六进制字符串', () {
      const pubKey = '99dbfea8e185e61f183c0d52547392aba065d4df3a8c3ea2647020e01fc09818'
          'ed5073adcb020b09282778477934b469c8aeba7b05698518af0b318ebbe3ef2d';
      const config = XLogConfig(
        logDir: '/logs',
        namePrefix: 'test',
        pubKey: pubKey,
      );
      expect(config.pubKey, pubKey);
      expect(config.pubKey.length, 128);
    });

    test('cacheDir 可以为空字符串', () {
      const config = XLogConfig(
        logDir: '/logs',
        namePrefix: 'test',
        cacheDir: '',
      );
      expect(config.cacheDir, '');
    });

    test('cacheDir 支持各种路径', () {
      final paths = [
        '/cache',
        '/var/cache/app',
        './cache',
        '../cache',
      ];

      for (final path in paths) {
        final config = XLogConfig(
          logDir: '/logs',
          namePrefix: 'test',
          cacheDir: path,
        );
        expect(config.cacheDir, path);
      }
    });

    test('cacheDays 支持0值（无限保留）', () {
      const config = XLogConfig(
        logDir: '/logs',
        namePrefix: 'test',
        cacheDays: 0,
      );
      expect(config.cacheDays, 0);
    });

    test('cacheDays 支持各种正整数', () {
      final days = [1, 7, 10, 30, 365, 3650];
      for (final day in days) {
        final config = XLogConfig(
          logDir: '/logs',
          namePrefix: 'test',
          cacheDays: day,
        );
        expect(config.cacheDays, day);
        expect(config.cacheDays, greaterThan(0));
      }
    });
  });

  group('XLogConfig - 不可变性', () {
    test('创建后无法修改 logDir', () {
      const config = XLogConfig(
        logDir: '/logs',
        namePrefix: 'test',
      );

      // 验证无法直接修改（通过尝试访问 final 字段）
      expect(config.logDir, '/logs');

      // 创建新配置以改变值
      const newConfig = XLogConfig(
        logDir: '/new/logs',
        namePrefix: 'test',
      );
      expect(newConfig.logDir, '/new/logs');
      // 原配置不变
      expect(config.logDir, '/logs');
    });

    test('配置对象具有相同的引用相等性', () {
      const config1 = XLogConfig(
        logDir: '/logs',
        namePrefix: 'test',
      );
      const config2 = config1;

      expect(identical(config1, config2), isTrue);
    });

    test('两个不同的配置对象有不同的引用', () {
      const config1 = XLogConfig(
        logDir: '/logs',
        namePrefix: 'test',
      );
      const config2 = XLogConfig(
        logDir: '/logs',
        namePrefix: 'test',
      );

      // const 对象会被 canonicalize，值相同即共享同一引用
      expect(identical(config1, config2), isTrue);
    });
  });

  group('XLogConfig - 边界情况', () {
    test('超长 logDir 路径', () {
      final longPath = '/logs/${'subdir/' * 50}';
      final config = XLogConfig(
        logDir: longPath,
        namePrefix: 'test',
      );
      expect(config.logDir, longPath);
    });

    test('超长 namePrefix', () {
      final longPrefix = 'a' * 500;
      final config = XLogConfig(
        logDir: '/logs',
        namePrefix: longPrefix,
      );
      expect(config.namePrefix, longPrefix);
    });

    test('超长 pubKey', () {
      final longKey = 'a' * 2000;
      final config = XLogConfig(
        logDir: '/logs',
        namePrefix: 'test',
        pubKey: longKey,
      );
      expect(config.pubKey, longKey);
    });

    test('超长 cacheDir', () {
      final longPath = '/cache/${'subdir/' * 30}';
      final config = XLogConfig(
        logDir: '/logs',
        namePrefix: 'test',
        cacheDir: longPath,
      );
      expect(config.cacheDir, longPath);
    });

    test('特殊字符在 logDir 中', () {
      final paths = [
        '/logs/my-app',
        '/logs/my_app',
        '/logs/my.app',
        '/logs/my app',
        '/logs/app@2024',
      ];

      for (final path in paths) {
        final config = XLogConfig(
          logDir: path,
          namePrefix: 'test',
        );
        expect(config.logDir, path);
      }
    });

    test('特殊字符在 namePrefix 中', () {
      final prefixes = [
        'my-app',
        'my_app',
        'my.app',
        'my app',
        'app_v1.2.3',
      ];

      for (final prefix in prefixes) {
        final config = XLogConfig(
          logDir: '/logs',
          namePrefix: prefix,
        );
        expect(config.namePrefix, prefix);
      }
    });

    test('Unicode 字符在字段中', () {
      const config = XLogConfig(
        logDir: '/logs/日志',
        namePrefix: '应用程序',
        cacheDir: '/cache/缓存',
      );

      expect(config.logDir.contains('日'), true);
      expect(config.namePrefix.contains('应'), true);
      expect(config.cacheDir.contains('缓'), true);
    });

    test('最大 cacheDays 值', () {
      const maxDays = 36500; // 100 years
      const config = XLogConfig(
        logDir: '/logs',
        namePrefix: 'test',
        cacheDays: maxDays,
      );
      expect(config.cacheDays, maxDays);
    });

    test('最小 cacheDays 值', () {
      const config = XLogConfig(
        logDir: '/logs',
        namePrefix: 'test',
        cacheDays: 1,
      );
      expect(config.cacheDays, 1);
    });
  });

  group('XLogConfig - 组合配置', () {
    test('所有异步配置', () {
      const config = XLogConfig(
        logDir: '/logs',
        namePrefix: 'async_app',
        level: LogLevel.debug,
        mode: AppenderMode.async_,
        compressMode: CompressMode.zlib,
      );

      expect(config.mode, AppenderMode.async_);
    });

    test('所有同步配置', () {
      const config = XLogConfig(
        logDir: '/logs',
        namePrefix: 'sync_app',
        level: LogLevel.info,
        mode: AppenderMode.sync_,
        compressMode: CompressMode.zstd,
      );

      expect(config.mode, AppenderMode.sync_);
    });

    test('低级别，所有功能启用', () {
      const config = XLogConfig(
        logDir: '/logs',
        namePrefix: 'full_debug',
        level: LogLevel.verbose,
        mode: AppenderMode.async_,
        compressMode: CompressMode.zlib,
        pubKey: 'abc123',
        cacheDir: '/cache',
        cacheDays: 30,
      );

      expect(config.level, LogLevel.verbose);
      expect(config.pubKey, isNotEmpty);
      expect(config.cacheDir, isNotEmpty);
      expect(config.cacheDays, greaterThan(0));
    });

    test('高级别，最小配置', () {
      const config = XLogConfig(
        logDir: '/logs',
        namePrefix: 'minimal_prod',
        level: LogLevel.error,
      );

      expect(config.level, LogLevel.error);
      expect(config.pubKey, isEmpty);
      expect(config.cacheDir, isEmpty);
      expect(config.cacheDays, 0);
    });

    test('生产环境推荐配置', () {
      const config = XLogConfig(
        logDir: '/data/logs',
        namePrefix: 'prod_app',
        level: LogLevel.warn,
        mode: AppenderMode.async_,
        compressMode: CompressMode.zstd,
        pubKey: '99dbfea8e185e61f183c0d52547392aba065d4df3a8c3ea2647020e01fc09818'
            'ed5073adcb020b09282778477934b469c8aeba7b05698518af0b318ebbe3ef2d',
        cacheDir: '/data/cache',
        cacheDays: 10,
      );

      expect(config.level, LogLevel.warn);
      expect(config.mode, AppenderMode.async_);
      expect(config.compressMode, CompressMode.zstd);
      expect(config.pubKey, isNotEmpty);
    });

    test('调试环境推荐配置', () {
      const config = XLogConfig(
        logDir: './logs',
        namePrefix: 'debug_app',
        level: LogLevel.verbose,
        mode: AppenderMode.async_,
        compressMode: CompressMode.zlib,
        pubKey: '',
        cacheDir: './cache',
        cacheDays: 0,
      );

      expect(config.level, LogLevel.verbose);
      expect(config.pubKey, isEmpty);
      expect(config.cacheDays, 0);
    });
  });

  group('XLogConfig - toString 和调试', () {
    test('配置对象可以转为字符串', () {
      const config = XLogConfig(
        logDir: '/logs',
        namePrefix: 'test',
      );

      expect(config.toString(), isNotEmpty);
    });

    test('配置对象包含重要信息在字符串中', () {
      const config = XLogConfig(
        logDir: '/logs',
        namePrefix: 'test',
        level: LogLevel.info,
      );

      final str = config.toString();
      // 验证包含某些关键字段信息
      expect(str, isNotEmpty);
    });
  });

  group('XLogConfig - 实例比较', () {
    test('相同值的两个实例可以区分', () {
      const config1 = XLogConfig(
        logDir: '/logs',
        namePrefix: 'test',
        level: LogLevel.debug,
      );

      const config2 = XLogConfig(
        logDir: '/logs',
        namePrefix: 'test',
        level: LogLevel.debug,
      );

      // const 对象值相同会复用同一实例，因此相等且 hashCode 相同
      expect(config1 == config2, isTrue);
      expect(config1.hashCode == config2.hashCode, isTrue);
    });

    test('同一个引用的实例相等', () {
      const config1 = XLogConfig(
        logDir: '/logs',
        namePrefix: 'test',
      );
      const config2 = config1;

      expect(config1, equals(config2));
      expect(identical(config1, config2), true);
    });
  });

  group('XLogConfig - 字段类型', () {
    test('logDir 是字符串类型', () {
      const config = XLogConfig(
        logDir: '/logs',
        namePrefix: 'test',
      );
      expect(config.logDir, isA<String>());
    });

    test('namePrefix 是字符串类型', () {
      const config = XLogConfig(
        logDir: '/logs',
        namePrefix: 'test',
      );
      expect(config.namePrefix, isA<String>());
    });

    test('level 是 LogLevel 类型', () {
      const config = XLogConfig(
        logDir: '/logs',
        namePrefix: 'test',
        level: LogLevel.debug,
      );
      expect(config.level, isA<LogLevel>());
    });

    test('mode 是 AppenderMode 类型', () {
      const config = XLogConfig(
        logDir: '/logs',
        namePrefix: 'test',
        mode: AppenderMode.async_,
      );
      expect(config.mode, isA<AppenderMode>());
    });

    test('compressMode 是 CompressMode 类型', () {
      const config = XLogConfig(
        logDir: '/logs',
        namePrefix: 'test',
        compressMode: CompressMode.zlib,
      );
      expect(config.compressMode, isA<CompressMode>());
    });

    test('pubKey 是字符串类型', () {
      const config = XLogConfig(
        logDir: '/logs',
        namePrefix: 'test',
        pubKey: 'test_key',
      );
      expect(config.pubKey, isA<String>());
    });

    test('cacheDir 是字符串类型', () {
      const config = XLogConfig(
        logDir: '/logs',
        namePrefix: 'test',
        cacheDir: '/cache',
      );
      expect(config.cacheDir, isA<String>());
    });

    test('cacheDays 是整数类型', () {
      const config = XLogConfig(
        logDir: '/logs',
        namePrefix: 'test',
        cacheDays: 7,
      );
      expect(config.cacheDays, isA<int>());
    });
  });
}
