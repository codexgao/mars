// Single entry point for all xlog_flutter integration tests.
//
// Run with:
//   flutter test integration_test/xlog_all_test.dart -d macos
//   flutter test integration_test/xlog_all_test.dart -d ios
//   flutter test integration_test/xlog_all_test.dart -d android
//
// This file imports all test groups so they run in a single app process.
// Running individual test files directly also works but may fail when run
// together via `flutter test integration_test/` because Flutter restarts
// the app for each file, which can conflict with xlog's file locks.

import 'package:integration_test/integration_test.dart';

import 'xlog_open_test.dart' as open_tests;
import 'xlog_write_test.dart' as write_tests;
import 'xlog_level_test.dart' as level_tests;
import 'xlog_control_test.dart' as control_tests;
import 'xlog_multi_instance_test.dart' as multi_tests;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  open_tests.main();
  write_tests.main();
  level_tests.main();
  control_tests.main();
  multi_tests.main();
}
