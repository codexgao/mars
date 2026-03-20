import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'xlog_flutter_bindings_generated.dart';

// ---------------------------------------------------------------------------
// Public enumerations
// ---------------------------------------------------------------------------

enum LogLevel {
  verbose, // 0
  debug,   // 1
  info,    // 2
  warn,    // 3
  error,   // 4
  fatal,   // 5
  none,    // 6
}

enum AppenderMode {
  async_, // 0
  sync_,  // 1
}

enum CompressMode {
  zlib, // 0
  zstd, // 1
}

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

class XLogConfig {
  /// Directory where log files are written. Must be writable.
  final String logDir;

  /// Prefix for log file names (e.g. "myapp").
  final String namePrefix;

  /// Minimum log level. Messages below this level are discarded.
  final LogLevel level;

  /// Async (default) or sync write mode.
  final AppenderMode mode;

  /// Compression algorithm used for log files.
  final CompressMode compressMode;

  /// Optional public key for log file encryption (ECC). Empty string disables encryption.
  final String pubKey;

  /// Optional cache directory. Use the app's cache dir to avoid SIGBUS on Android.
  /// If empty, no separate cache is used.
  final String cacheDir;

  /// How many days to keep old log files. 0 = unlimited.
  final int cacheDays;

  const XLogConfig({
    required this.logDir,
    required this.namePrefix,
    this.level = LogLevel.debug,
    this.mode = AppenderMode.async_,
    this.compressMode = CompressMode.zlib,
    this.pubKey = '',
    this.cacheDir = '',
    this.cacheDays = 0,
  });
}

// ---------------------------------------------------------------------------
// XLog static API
// ---------------------------------------------------------------------------

/// High-level wrapper around the mars xlog C library.
///
/// Usage:
/// ```dart
/// XLog.open(XLogConfig(logDir: '/path/to/logs', namePrefix: 'myapp'));
/// XLog.info('MyTag', 'Application started');
/// // ... at shutdown:
/// XLog.close();
/// ```
class XLog {
  XLog._();

  // -------------------------------------------------------------------------
  // Lifecycle
  // -------------------------------------------------------------------------

  /// Open the xlog appender. Call once at application startup before any
  /// log writes. [config] controls log directory, compression, etc.
  static void open(XLogConfig config) {
    final logDir   = config.logDir.toNativeUtf8();
    final prefix   = config.namePrefix.toNativeUtf8();
    final pubKey   = config.pubKey.toNativeUtf8();
    final cacheDir = config.cacheDir.toNativeUtf8();
    try {
      _bindings.xlog_open(
        config.mode.index,
        config.level.index,
        logDir.cast(),
        prefix.cast(),
        pubKey.cast(),
        config.compressMode.index,
        cacheDir.cast(),
        config.cacheDays,
      );
    } finally {
      malloc.free(logDir);
      malloc.free(prefix);
      malloc.free(pubKey);
      malloc.free(cacheDir);
    }
  }

  /// Flush buffered logs to disk. Returns immediately (async flush).
  static void flush() => _bindings.xlog_flush(0);

  /// Flush buffered logs synchronously. Blocks until all pending data is written.
  static void flushSync() => _bindings.xlog_flush(1);

  /// Close the xlog appender. Flushes remaining data. Call at application shutdown.
  static void close() => _bindings.xlog_close();

  // -------------------------------------------------------------------------
  // Log writing
  // -------------------------------------------------------------------------

  static void verbose(String tag, String message,
      {String filename = '', String funcname = '', int line = 0}) =>
      _write(LogLevel.verbose, tag, message, filename, funcname, line);

  static void debug(String tag, String message,
      {String filename = '', String funcname = '', int line = 0}) =>
      _write(LogLevel.debug, tag, message, filename, funcname, line);

  static void info(String tag, String message,
      {String filename = '', String funcname = '', int line = 0}) =>
      _write(LogLevel.info, tag, message, filename, funcname, line);

  static void warn(String tag, String message,
      {String filename = '', String funcname = '', int line = 0}) =>
      _write(LogLevel.warn, tag, message, filename, funcname, line);

  static void error(String tag, String message,
      {String filename = '', String funcname = '', int line = 0}) =>
      _write(LogLevel.error, tag, message, filename, funcname, line);

  static void fatal(String tag, String message,
      {String filename = '', String funcname = '', int line = 0}) =>
      _write(LogLevel.fatal, tag, message, filename, funcname, line);

  // -------------------------------------------------------------------------
  // Runtime configuration
  // -------------------------------------------------------------------------

  /// Enable or disable console (stdout/logcat) output.
  static void setConsoleLog(bool enable) =>
      _bindings.xlog_set_console_log(enable ? 1 : 0);

  /// Change the minimum log level at runtime.
  static void setLevel(LogLevel level) =>
      _bindings.xlog_set_level(level.index);

  /// Set the maximum size (bytes) for a single log file. 0 = unlimited.
  static void setMaxFileSize(int maxBytes) =>
      _bindings.xlog_set_max_file_size(maxBytes);

  /// Set how long (seconds) to keep old log files. Default 10 days = 864000.
  static void setMaxAliveDuration(int maxSeconds) =>
      _bindings.xlog_set_max_alive_duration(maxSeconds);

  // -------------------------------------------------------------------------
  // Internal
  // -------------------------------------------------------------------------

  static void _write(LogLevel level, String tag, String message,
      String filename, String funcname, int line) {
    final nTag     = tag.toNativeUtf8();
    final nFile    = filename.toNativeUtf8();
    final nFunc    = funcname.toNativeUtf8();
    final nMessage = message.toNativeUtf8();
    try {
      _bindings.xlog_write(
        level.index,
        nTag.cast(),
        nFile.cast(),
        nFunc.cast(),
        line,
        nMessage.cast(),
      );
    } finally {
      malloc.free(nTag);
      malloc.free(nFile);
      malloc.free(nFunc);
      malloc.free(nMessage);
    }
  }
}

// ---------------------------------------------------------------------------
// Native library loading
// ---------------------------------------------------------------------------

const String _libName = 'xlog_flutter';

final DynamicLibrary _dylib = () {
  if (Platform.isMacOS || Platform.isIOS) {
    return DynamicLibrary.open('$_libName.framework/$_libName');
  }
  if (Platform.isAndroid || Platform.isLinux) {
    return DynamicLibrary.open('lib$_libName.so');
  }
  if (Platform.isWindows) {
    return DynamicLibrary.open('$_libName.dll');
  }
  throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
}();

final XlogFlutterBindings _bindings = XlogFlutterBindings(_dylib);
