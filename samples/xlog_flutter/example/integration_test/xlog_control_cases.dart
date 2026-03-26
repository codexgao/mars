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
    await XlogTestUtils.tearDown('test_control_instance');
  });

  group('XLog Control Methods', () {
    test('appenderMode can be set to sync', () async {
      final config = XLogConfig(
        logdir: tempLogDir.path,
        nameprefix: 'test_control_instance',
      );
      final instance = XLog.open(config);
      instance.appenderMode = XLogAppenderMode.sync;
    });

    test('appenderMode can be set to async_', () async {
      final config = XLogConfig(
        logdir: tempLogDir.path,
        nameprefix: 'test_control_instance',
      );
      final instance = XLog.open(config);
      instance.appenderMode = XLogAppenderMode.async_;
    });

    test('consoleLogOpen can be set to true', () async {
      final config = XLogConfig(
        logdir: tempLogDir.path,
        nameprefix: 'test_control_instance',
      );
      final instance = XLog.open(config);
      instance.consoleLogOpen = true;
    });

    test('consoleLogOpen can be set to false', () async {
      final config = XLogConfig(
        logdir: tempLogDir.path,
        nameprefix: 'test_control_instance',
      );
      final instance = XLog.open(config);
      instance.consoleLogOpen = false;
    });

    test('flush with sync: true does not crash', () async {
      final config = XLogConfig(
        logdir: tempLogDir.path,
        nameprefix: 'test_control_instance',
      );
      final instance = XLog.open(config);
      instance.info('tag', 'message');
      instance.flush(sync: true);
    });

    test('flush with sync: false does not crash', () async {
      final config = XLogConfig(
        logdir: tempLogDir.path,
        nameprefix: 'test_control_instance',
      );
      final instance = XLog.open(config);
      instance.info('tag', 'message');
      instance.flush(sync: false);
      await Future.delayed(Duration(milliseconds: 100));
    });

    test('logPath is non-empty after open', () async {
      final config = XLogConfig(
        logdir: tempLogDir.path,
        nameprefix: 'test_control_instance',
      );
      final instance = XLog.open(config);

      final logPath = instance.logPath;
      expect(logPath, isNotNull);
      expect(logPath, isNotEmpty);
    });
  });
}
