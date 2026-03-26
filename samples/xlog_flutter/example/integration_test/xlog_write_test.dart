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
      expect(logPath, isNotNull);
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

    test('compression mode zlib generates file', () async {
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
    });

    test('compression mode zstd generates file', () async {
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
    });

    test('encryption with pubKey generates file', () async {
      const pubKey =
          '5785f0bd2b145d6fb3acba287cabfdbb96ed6053679ef7b7e0c77ff134f2a86776fe93e77fbed209a93e9165556be8f2d65b6be730da6529e8533643a657e5b1';
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

      // Encrypted file should have non-trivial size
      int totalSize = 0;
      for (final file in files) {
        totalSize += await XlogTestUtils.getFileSize(file);
      }
      expect(totalSize, greaterThan(0));
    });

    test('cachedir config does not crash', () async {
      final cacheDir = '${tempLogDir.path}/cache';
      final config = XLogConfig(
        logdir: tempLogDir.path,
        nameprefix: 'test_write_instance',
        cachedir: cacheDir,
      );
      final instance = XLog.open(config);

      instance.info('tag', 'cache dir test');
      instance.flush(sync: true);
    });

    test('cacheDays config does not crash', () async {
      final config = XLogConfig(
        logdir: tempLogDir.path,
        nameprefix: 'test_write_instance',
        cacheDays: 7,
      );
      final instance = XLog.open(config);

      instance.info('tag', 'cache days test');
      instance.flush(sync: true);
    });
  });
}
