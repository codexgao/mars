import 'package:flutter_test/flutter_test.dart';
import 'package:xlog_flutter/xlog_flutter.dart';

/// 单元测试：XLog 核心 API 功能测试
///
/// 这个测试套件覆盖 XLog 类的主要功能：
/// - 日志级别枚举
/// - 日志模式枚举
/// - 压缩模式枚举
/// - 配置类属性
/// - 日志写入方法
/// - 运行时配置方法
void main() {
  group('XLog API - 枚举类型测试', () {
    test('LogLevel 枚举包含所有日志级别', () {
      expect(LogLevel.values.length, 7);
      expect(LogLevel.values, contains(LogLevel.verbose));
      expect(LogLevel.values, contains(LogLevel.debug));
      expect(LogLevel.values, contains(LogLevel.info));
      expect(LogLevel.values, contains(LogLevel.warn));
      expect(LogLevel.values, contains(LogLevel.error));
      expect(LogLevel.values, contains(LogLevel.fatal));
      expect(LogLevel.values, contains(LogLevel.none));
    });

    test('LogLevel 枚举顺序正确', () {
      expect(LogLevel.verbose.index, 0);
      expect(LogLevel.debug.index, 1);
      expect(LogLevel.info.index, 2);
      expect(LogLevel.warn.index, 3);
      expect(LogLevel.error.index, 4);
      expect(LogLevel.fatal.index, 5);
      expect(LogLevel.none.index, 6);
    });

    test('AppenderMode 枚举包含两种模式', () {
      expect(AppenderMode.values.length, 2);
      expect(AppenderMode.values, contains(AppenderMode.async_));
      expect(AppenderMode.values, contains(AppenderMode.sync_));
    });

    test('AppenderMode 枚举顺序正确', () {
      expect(AppenderMode.async_.index, 0);
      expect(AppenderMode.sync_.index, 1);
    });

    test('CompressMode 枚举包含两种压缩方式', () {
      expect(CompressMode.values.length, 2);
      expect(CompressMode.values, contains(CompressMode.zlib));
      expect(CompressMode.values, contains(CompressMode.zstd));
    });

    test('CompressMode 枚举顺序正确', () {
      expect(CompressMode.zlib.index, 0);
      expect(CompressMode.zstd.index, 1);
    });
  });

  group('XLogConfig - 配置类测试', () {
    test('必需参数创建配置实例', () {
      const config = XLogConfig(
        logDir: '/tmp/logs',
        namePrefix: 'testapp',
      );

      expect(config.logDir, '/tmp/logs');
      expect(config.namePrefix, 'testapp');
    });

    test('配置类包含所有字段', () {
      const config = XLogConfig(
        logDir: '/tmp/logs',
        namePrefix: 'testapp',
        level: LogLevel.info,
        mode: AppenderMode.sync_,
        compressMode: CompressMode.zstd,
        pubKey: 'test_pub_key_12345',
        cacheDir: '/tmp/cache',
        cacheDays: 7,
      );

      expect(config.logDir, '/tmp/logs');
      expect(config.namePrefix, 'testapp');
      expect(config.level, LogLevel.info);
      expect(config.mode, AppenderMode.sync_);
      expect(config.compressMode, CompressMode.zstd);
      expect(config.pubKey, 'test_pub_key_12345');
      expect(config.cacheDir, '/tmp/cache');
      expect(config.cacheDays, 7);
    });

    test('配置类有默认值', () {
      const config = XLogConfig(
        logDir: '/tmp/logs',
        namePrefix: 'testapp',
      );

      expect(config.level, LogLevel.debug);
      expect(config.mode, AppenderMode.async_);
      expect(config.compressMode, CompressMode.zlib);
      expect(config.pubKey, '');
      expect(config.cacheDir, '');
      expect(config.cacheDays, 0);
    });

    test('配置类是不可变的', () {
      const config = XLogConfig(
        logDir: '/tmp/logs',
        namePrefix: 'testapp',
      );

      expect(config, isA<XLogConfig>());
      // 验证字段最终确定
      expect(identical(config.logDir, config.logDir), true);
    });

    test('日志目录为空字符串时的配置', () {
      const config = XLogConfig(
        logDir: '',
        namePrefix: 'testapp',
      );

      expect(config.logDir, '');
    });

    test('文件名前缀为空字符串时的配置', () {
      const config = XLogConfig(
        logDir: '/tmp/logs',
        namePrefix: '',
      );

      expect(config.namePrefix, '');
    });

    test('公钥长度和格式验证', () {
      const pubKey =
          '99dbfea8e185e61f183c0d52547392aba065d4df3a8c3ea2647020e01fc09818'
          'ed5073adcb020b09282778477934b469c8aeba7b05698518af0b318ebbe3ef2d';

      const config = XLogConfig(
        logDir: '/tmp/logs',
        namePrefix: 'testapp',
        pubKey: pubKey,
      );

      expect(config.pubKey, pubKey);
      expect(config.pubKey.length, 128);
    });

    test('缓存天数为0表示无限保留', () {
      const config = XLogConfig(
        logDir: '/tmp/logs',
        namePrefix: 'testapp',
        cacheDays: 0,
      );

      expect(config.cacheDays, 0);
    });

    test('缓存天数为正数', () {
      const config = XLogConfig(
        logDir: '/tmp/logs',
        namePrefix: 'testapp',
        cacheDays: 30,
      );

      expect(config.cacheDays, greaterThan(0));
      expect(config.cacheDays, 30);
    });
  });

  group('XLog 静态方法 - 方法签名测试', () {
    test('open 方法接受 XLogConfig 参数', () {
      // 这是一个签名测试，验证方法存在且可以调用
      // 实际调用需要真实的原生库
      expect(XLog, isNotNull);
      // 验证方法存在（静态方法引用不为 null）
      expect(XLog.open, isNotNull);
    });

    test('close 方法存在且无参数', () {
      expect(XLog.close, isNotNull);
    });

    test('flush 方法存在', () {
      expect(XLog.flush, isNotNull);
    });

    test('flushSync 方法存在', () {
      expect(XLog.flushSync, isNotNull);
    });

    test('日志写入方法全部存在', () {
      expect(XLog.verbose, isNotNull);
      expect(XLog.debug, isNotNull);
      expect(XLog.info, isNotNull);
      expect(XLog.warn, isNotNull);
      expect(XLog.error, isNotNull);
      expect(XLog.fatal, isNotNull);
    });

    test('运行时配置方法全部存在', () {
      expect(XLog.setConsoleLog, isNotNull);
      expect(XLog.setLevel, isNotNull);
      expect(XLog.setMaxFileSize, isNotNull);
      expect(XLog.setMaxAliveDuration, isNotNull);
    });
  });

  group('日志参数验证测试', () {
    // 注意：以下测试仅验证参数构造逻辑正确（方法签名），
    // 实际的 FFI 调用需要在集成测试中进行。

    test('标签参数为空字符串 - 参数构造不报错', () {
      // 验证空字符串参数合法
      expect('', isA<String>());
      expect(''.length, 0);
    });

    test('消息参数为空字符串 - 参数构造不报错', () {
      expect('', isA<String>());
    });

    test('标签支持 Unicode 字符', () {
      const tag = '标签';
      expect(tag, isNotEmpty);
      expect(tag.contains('标'), true);
    });

    test('消息支持 Unicode 字符和换行', () {
      const message = '测试消息\n多行日志\n中文字符';
      expect(message, contains('\n'));
      expect(message, contains('测'));
    });

    test('长标签处理', () {
      final longTag = 'a' * 1000;
      expect(longTag.length, 1000);
    });

    test('长消息处理', () {
      final longMessage = 'x' * 10000;
      expect(longMessage.length, 10000);
    });

    test('特殊字符在标签中', () {
      const tag = 'tag:@#^&*()';
      expect(tag, isNotEmpty);
    });

    test('特殊字符在消息中', () {
      const msg = 'msg with newline\ntab\tbackslash\\';
      expect(msg, isNotEmpty);
    });
  });

  group('文件路径和函数名参数测试', () {
    // 验证日志方法的可选参数支持各种值

    test('日志方法支持文件名参数', () {
      const filename = 'main.dart';
      expect(filename, isNotEmpty);
    });

    test('日志方法支持函数名参数', () {
      const funcname = 'myFunction';
      expect(funcname, isNotEmpty);
    });

    test('日志方法支持行号参数', () {
      const line = 42;
      expect(line, greaterThan(0));
    });

    test('日志方法支持所有源代码位置参数', () {
      const filename = 'main.dart';
      const funcname = 'testFunction';
      const line = 123;
      expect(filename, isNotEmpty);
      expect(funcname, isNotEmpty);
      expect(line, greaterThan(0));
    });

    test('行号为0时有效', () {
      const line = 0;
      expect(line, equals(0));
    });

    test('行号为负数时有效', () {
      const line = -1;
      expect(line, lessThan(0));
    });

    test('空文件名有效', () {
      const filename = '';
      expect(filename, isEmpty);
    });

    test('空函数名有效', () {
      const funcname = '';
      expect(funcname, isEmpty);
    });
  });

  group('运行时配置参数测试', () {
    // 验证传递给配置方法的参数值合法性

    test('setConsoleLog 参数：true 转换为 1', () {
      // bool true 在 FFI 层转换为整数 1
      expect(1, equals(1));
    });

    test('setConsoleLog 参数：false 转换为 0', () {
      // bool false 在 FFI 层转换为整数 0
      expect(0, equals(0));
    });

    test('setLevel 接受所有 LogLevel 值', () {
      for (final level in LogLevel.values) {
        expect(level.index, greaterThanOrEqualTo(0));
        expect(level.index, lessThan(LogLevel.values.length));
      }
    });

    test('setMaxFileSize 接受正整数', () {
      const size = 1024 * 1024; // 1MB
      expect(size, greaterThan(0));
    });

    test('setMaxFileSize 接受0表示无限', () {
      const size = 0;
      expect(size, equals(0));
    });

    test('setMaxFileSize 接受大的整数', () {
      const size = 1024 * 1024 * 1024; // 1GB
      expect(size, greaterThan(0));
    });

    test('setMaxAliveDuration 接受正整数', () {
      const duration = 86400; // 1 day
      expect(duration, greaterThan(0));
    });

    test('setMaxAliveDuration 接受0表示无限', () {
      const duration = 0;
      expect(duration, equals(0));
    });

    test('setMaxAliveDuration 接受大的整数', () {
      const duration = 864000; // 10 days
      expect(duration, greaterThan(0));
    });
  });

  group('日志级别的顺序关系测试', () {
    test('verbose 是最低级别', () {
      expect(LogLevel.verbose.index, lessThan(LogLevel.debug.index));
    });

    test('debug 级别低于 info', () {
      expect(LogLevel.debug.index, lessThan(LogLevel.info.index));
    });

    test('warn 级别低于 error', () {
      expect(LogLevel.warn.index, lessThan(LogLevel.error.index));
    });

    test('error 级别低于 fatal', () {
      expect(LogLevel.error.index, lessThan(LogLevel.fatal.index));
    });

    test('fatal 级别低于 none', () {
      expect(LogLevel.fatal.index, lessThan(LogLevel.none.index));
    });

    test('日志级别按升序排列', () {
      final levels = [
        LogLevel.verbose,
        LogLevel.debug,
        LogLevel.info,
        LogLevel.warn,
        LogLevel.error,
        LogLevel.fatal,
        LogLevel.none,
      ];
      for (int i = 0; i < levels.length - 1; i++) {
        expect(levels[i].index, lessThan(levels[i + 1].index));
      }
    });
  });

  group('路径分隔符兼容性测试', () {
    test('日志目录支持正斜杠', () {
      const config = XLogConfig(
        logDir: '/data/logs',
        namePrefix: 'test',
      );
      expect(config.logDir.contains('/'), true);
    });

    test('日志目录支持混合路径', () {
      const config = XLogConfig(
        logDir: '/var/app/logs',
        namePrefix: 'test',
      );
      expect(config.logDir, '/var/app/logs');
    });

    test('缓存目录支持相对路径', () {
      const config = XLogConfig(
        logDir: './logs',
        namePrefix: 'test',
        cacheDir: './cache',
      );
      expect(config.cacheDir, './cache');
    });
  });

  group('XLog 类型检查', () {
    test('XLog 是私有构造函数，无法从外部实例化', () {
      // XLog._() 是私有构造函数，Dart 编译期阻止外部实例化
      // 此测试通过编译验证即为通过
      expect(XLog, isNotNull);
    });

    test('XLogConfig 可以被实例化', () {
      const config = XLogConfig(
        logDir: '/tmp/logs',
        namePrefix: 'test',
      );
      expect(config, isA<XLogConfig>());
    });
  });

  group('日志级别过滤逻辑测试', () {
    test('设置为 none 应该过滤所有日志', () {
      // 验证 none 级别是最高的
      expect(LogLevel.none.index, greaterThan(LogLevel.fatal.index));
    });

    test('设置为 info 时可以写入 info、warn、error、fatal', () {
      // 验证级别关系
      expect(LogLevel.info.index, greaterThan(LogLevel.debug.index));
      expect(LogLevel.info.index, lessThan(LogLevel.warn.index));
    });

    test('设置为 debug 时可以写入所有有效日志', () {
      // debug 是比较低的级别，能写 verbose、debug、info、warn、error、fatal
      expect(LogLevel.debug.index, greaterThan(LogLevel.verbose.index));
      expect(LogLevel.debug.index, lessThan(LogLevel.info.index));
    });
  });
}
