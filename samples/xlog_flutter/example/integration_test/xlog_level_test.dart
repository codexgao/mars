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

      // Note: XLOG_LEVEL_ALL and XLOG_LEVEL_VERBOSE share the same native value (0).
      // Round-tripping through native layer returns XLogLevel.all for both.
      // Verify settable levels that have distinct native values:
      final uniqueLevels = [
        XLogLevel.debug,
        XLogLevel.info,
        XLogLevel.warn,
        XLogLevel.error,
        XLogLevel.fatal,
        XLogLevel.none,
      ];

      for (final level in uniqueLevels) {
        instance.level = level;
        expect(instance.level, equals(level));
      }

      // For all/verbose (both map to native 0), just verify no crash:
      instance.level = XLogLevel.all;
      instance.level = XLogLevel.verbose;
    });
  });
}
