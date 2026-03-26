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
    await XlogTestUtils.tearDown('test_multi_1');
    await XlogTestUtils.tearDown('test_multi_2');
  });

  group('XLog Multi-Instance', () {
    test('two instances share same logPath but have separate files', () async {
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

      expect(instance1.logPath, isNotNull);
      expect(instance2.logPath, isNotNull);
      expect(instance1.logPath, isNotEmpty);
      expect(instance2.logPath, isNotEmpty);
      
      // Both instances should share the same logPath (logdir)
      expect(instance1.logPath, equals(instance2.logPath));
      
      // Write to both instances
      instance1.info('tag', 'message from instance 1');
      instance1.flush(sync: true);
      
      instance2.info('tag', 'message from instance 2');
      instance2.flush(sync: true);
      
      // But their log files should be separate (different nameprefix)
      final files1 = await XlogTestUtils.getLogFiles(instance1);
      final files2 = await XlogTestUtils.getLogFiles(instance2);
      
      expect(files1, isNotEmpty);
      expect(files2, isNotEmpty);
      
      // Verify each instance's files contain its nameprefix
      expect(files1.any((f) => f.path.contains('test_multi_1')), isTrue);
      expect(files2.any((f) => f.path.contains('test_multi_2')), isTrue);
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

      instance1.appenderMode = XLogAppenderMode.sync;
      instance2.appenderMode = XLogAppenderMode.async_;
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

      XLog.open(config1);
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
