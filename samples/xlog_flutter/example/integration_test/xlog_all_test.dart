// Single entry point for all xlog_flutter integration tests.
//
// Run with:
//   flutter test integration_test/ -d macos
//   flutter test integration_test/ -d ios
//   flutter test integration_test/ -d android
//
// Sub-test modules are named *_cases.dart (not *_test.dart) so that Flutter's
// test runner only discovers this file as the entry point, ensuring all tests
// run in a single app process. This avoids xlog file-lock conflicts that occur
// when Flutter restarts the app for each discovered test file.

import 'package:integration_test/integration_test.dart';

import 'xlog_open_cases.dart' as open_tests;
import 'xlog_write_cases.dart' as write_tests;
import 'xlog_level_cases.dart' as level_tests;
import 'xlog_control_cases.dart' as control_tests;
import 'xlog_multi_instance_cases.dart' as multi_tests;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  open_tests.main();
  write_tests.main();
  level_tests.main();
  control_tests.main();
  multi_tests.main();
}
