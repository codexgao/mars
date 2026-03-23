/// xlog_flutter — Flutter FFI plugin for mars xlog multi-instance logging.
///
/// Usage:
/// ```dart
/// import 'package:xlog_flutter/xlog_flutter.dart';
///
/// // Initialize (loads native library)
/// XLog.initialize();
///
/// // Open a log instance
/// final log = XLog.open(XLogConfig(
///   logdir: '/path/to/logs',
///   nameprefix: 'myapp',
/// ));
///
/// // Write logs
/// log.info('app', 'Hello from xlog!');
///
/// // Flush and close
/// log.flush(sync: true);
/// XLog.release('myapp');
/// ```
library xlog_flutter;

export 'src/xlog.dart';
