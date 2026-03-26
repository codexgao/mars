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
      expect(instance.handle, greaterThan(0));
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
    });

    test('release() on non-existent name does not crash', () async {
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
