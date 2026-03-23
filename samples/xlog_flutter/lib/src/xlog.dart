import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import '../xlog_flutter_bindings_generated.dart';

/// Log level for xlog operations.
enum XLogLevel {
  all(xlog_level_t.XLOG_LEVEL_ALL),
  verbose(xlog_level_t.XLOG_LEVEL_VERBOSE),
  debug(xlog_level_t.XLOG_LEVEL_DEBUG),
  info(xlog_level_t.XLOG_LEVEL_INFO),
  warn(xlog_level_t.XLOG_LEVEL_WARN),
  error(xlog_level_t.XLOG_LEVEL_ERROR),
  fatal(xlog_level_t.XLOG_LEVEL_FATAL),
  none(xlog_level_t.XLOG_LEVEL_NONE);

  const XLogLevel(this.value);
  final int value;

  static XLogLevel fromValue(int value) {
    return XLogLevel.values.firstWhere(
      (e) => e.value == value,
      orElse: () => XLogLevel.debug,
    );
  }
}

/// Appender mode for xlog instances.
enum XLogAppenderMode {
  async_(xlog_appender_mode_t.XLOG_APPENDER_ASYNC),
  sync(xlog_appender_mode_t.XLOG_APPENDER_SYNC);

  const XLogAppenderMode(this.value);
  final int value;
}

/// Compression mode for xlog instances.
enum XLogCompressMode {
  zlib(xlog_compress_mode_t.XLOG_COMPRESS_ZLIB),
  zstd(xlog_compress_mode_t.XLOG_COMPRESS_ZSTD);

  const XLogCompressMode(this.value);
  final int value;
}

/// Configuration for creating an xlog instance.
class XLogConfig {
  /// Log output directory (required).
  final String logdir;

  /// Instance name prefix / identifier (required).
  final String nameprefix;

  /// Appender mode (async or sync). Defaults to async.
  final XLogAppenderMode mode;

  /// Encryption public key. Null means no encryption.
  final String? pubKey;

  /// Compression algorithm. Defaults to zlib.
  final XLogCompressMode compressMode;

  /// Compression level 0-9. Defaults to 0.
  final int compressLevel;

  /// Cache directory. Null means disabled.
  final String? cachedir;

  /// Cache retention in days. 0 means unlimited.
  final int cacheDays;

  const XLogConfig({
    required this.logdir,
    required this.nameprefix,
    this.mode = XLogAppenderMode.async_,
    this.pubKey,
    this.compressMode = XLogCompressMode.zlib,
    this.compressLevel = 0,
    this.cachedir,
    this.cacheDays = 0,
  });
}

/// A single xlog instance handle with convenience logging methods.
class XLogInstance {
  final int _handle;
  final XlogFlutterBindings _bindings;

  XLogInstance._(this._handle, this._bindings);

  /// The raw native handle value.
  int get handle => _handle;

  /// Whether this instance handle is valid (non-zero).
  bool get isValid => _handle != 0;

  // ---- Convenience log writers ----

  /// Write a verbose-level log message.
  void verbose(String tag, String message,
      {String filename = '', String funcname = '', int line = 0}) {
    _write(XLogLevel.verbose, tag, message, filename, funcname, line);
  }

  /// Write a debug-level log message.
  void debug(String tag, String message,
      {String filename = '', String funcname = '', int line = 0}) {
    _write(XLogLevel.debug, tag, message, filename, funcname, line);
  }

  /// Write an info-level log message.
  void info(String tag, String message,
      {String filename = '', String funcname = '', int line = 0}) {
    _write(XLogLevel.info, tag, message, filename, funcname, line);
  }

  /// Write a warn-level log message.
  void warn(String tag, String message,
      {String filename = '', String funcname = '', int line = 0}) {
    _write(XLogLevel.warn, tag, message, filename, funcname, line);
  }

  /// Write an error-level log message.
  void error(String tag, String message,
      {String filename = '', String funcname = '', int line = 0}) {
    _write(XLogLevel.error, tag, message, filename, funcname, line);
  }

  /// Write a fatal-level log message.
  void fatal(String tag, String message,
      {String filename = '', String funcname = '', int line = 0}) {
    _write(XLogLevel.fatal, tag, message, filename, funcname, line);
  }

  /// Write a log message at the specified level.
  void write(XLogLevel level, String tag, String message,
      {String filename = '', String funcname = '', int line = 0}) {
    _write(level, tag, message, filename, funcname, line);
  }

  void _write(XLogLevel level, String tag, String message, String filename,
      String funcname, int line) {
    final tagPtr = tag.toNativeUtf8();
    final filenamePtr = filename.toNativeUtf8();
    final funcnamePtr = funcname.toNativeUtf8();
    final msgPtr = message.toNativeUtf8();
    try {
      _bindings.xlog_write(
        _handle,
        level.value,
        tagPtr.cast(),
        filenamePtr.cast(),
        funcnamePtr.cast(),
        line,
        msgPtr.cast(),
      );
    } finally {
      calloc.free(tagPtr);
      calloc.free(filenamePtr);
      calloc.free(funcnamePtr);
      calloc.free(msgPtr);
    }
  }

  // ---- Level control ----

  /// Check if the given log level is enabled for this instance.
  bool isEnabledFor(XLogLevel level) {
    return _bindings.xlog_is_enabled_for(_handle, level.value) != 0;
  }

  /// Get the current log level.
  XLogLevel get level {
    return XLogLevel.fromValue(_bindings.xlog_get_level(_handle));
  }

  /// Set the log level.
  set level(XLogLevel level) {
    _bindings.xlog_set_level(_handle, level.value);
  }

  // ---- Control ----

  /// Set the appender mode (async or sync).
  set appenderMode(XLogAppenderMode mode) {
    _bindings.xlog_set_appender_mode(_handle, mode.value);
  }

  /// Enable or disable console log output.
  set consoleLogOpen(bool isOpen) {
    _bindings.xlog_set_console_log_open(_handle, isOpen ? 1 : 0);
  }

  /// Flush the log buffer. Set [sync] to true for synchronous flush.
  void flush({bool sync = false}) {
    _bindings.xlog_flush(_handle, sync ? 1 : 0);
  }

  /// Get the current log file path, or null if unavailable.
  String? get logPath {
    final buf = calloc<Char>(1024);
    try {
      final result = _bindings.xlog_get_log_path(_handle, buf, 1024);
      if (result != 0) {
        return buf.cast<Utf8>().toDartString();
      }
      return null;
    } finally {
      calloc.free(buf);
    }
  }
}

/// Singleton manager for xlog instances.
///
/// The native library is loaded automatically on first use.
///
/// ```dart
/// final instance = XLog.open(XLogConfig(
///   logdir: '/path/to/logs',
///   nameprefix: 'myapp',
/// ));
/// instance.info('tag', 'Hello!');
/// instance.flush(sync: true);
/// XLog.release('myapp');
/// ```
class XLog {
  XLog._();

  static XlogFlutterBindings? _bindings;

  /// Whether the native library has been loaded.
  static bool get isInitialized => _bindings != null;

  /// Load the native xlog library for the current platform.
  ///
  /// Called automatically on first use. Safe to call explicitly
  /// if you want to control when the library is loaded (e.g. at startup).
  static void initialize() {
    if (_bindings != null) return;

    final DynamicLibrary dylib;
    if (Platform.isWindows) {
      dylib = DynamicLibrary.open('xlog.dll');
    } else if (Platform.isMacOS) {
      dylib = DynamicLibrary.open('libxlog.dylib');
    } else if (Platform.isLinux) {
      dylib = DynamicLibrary.open('libxlog.so');
    } else if (Platform.isIOS) {
      dylib = DynamicLibrary.process();
    } else if (Platform.isAndroid) {
      dylib = DynamicLibrary.open('libxlog.so');
    } else {
      throw UnsupportedError(
          'xlog_flutter: unsupported platform ${Platform.operatingSystem}');
    }

    _bindings = XlogFlutterBindings(dylib);
  }

  static XlogFlutterBindings get _b {
    if (_bindings == null) initialize();
    return _bindings!;
  }

  /// Create a new xlog instance with the given configuration.
  ///
  /// Returns an [XLogInstance] with a valid handle on success.
  /// If an instance with the same [XLogConfig.nameprefix] already exists,
  /// returns the existing instance.
  static XLogInstance open(XLogConfig config, {XLogLevel level = XLogLevel.debug}) {
    final nativeConfig = calloc<xlog_config_t>();
    final logdirPtr = config.logdir.toNativeUtf8();
    final nameprefixPtr = config.nameprefix.toNativeUtf8();
    final pubKeyPtr = config.pubKey?.toNativeUtf8();
    final cachedirPtr = config.cachedir?.toNativeUtf8();

    try {
      nativeConfig.ref
        ..mode = config.mode.value
        ..logdir = logdirPtr.cast()
        ..nameprefix = nameprefixPtr.cast()
        ..pub_key = pubKeyPtr?.cast() ?? nullptr
        ..compress_mode = config.compressMode.value
        ..compress_level = config.compressLevel
        ..cachedir = cachedirPtr?.cast() ?? nullptr
        ..cache_days = config.cacheDays;

      final handle = _b.xlog_new_instance(nativeConfig, level.value);
      return XLogInstance._(handle, _b);
    } finally {
      calloc.free(nativeConfig);
      calloc.free(logdirPtr);
      calloc.free(nameprefixPtr);
      if (pubKeyPtr != null) calloc.free(pubKeyPtr);
      if (cachedirPtr != null) calloc.free(cachedirPtr);
    }
  }

  /// Get an existing instance by name prefix.
  ///
  /// Returns an [XLogInstance] with handle 0 if not found.
  static XLogInstance get(String nameprefix) {
    final ptr = nameprefix.toNativeUtf8();
    try {
      final handle = _b.xlog_get_instance(ptr.cast());
      return XLogInstance._(handle, _b);
    } finally {
      calloc.free(ptr);
    }
  }

  /// Check if an instance with the given name prefix exists.
  static bool has(String nameprefix) {
    final ptr = nameprefix.toNativeUtf8();
    try {
      return _b.xlog_has_instance(ptr.cast()) != 0;
    } finally {
      calloc.free(ptr);
    }
  }

  /// Release (close and destroy) an instance by name prefix.
  static void release(String nameprefix) {
    final ptr = nameprefix.toNativeUtf8();
    try {
      _b.xlog_release_instance(ptr.cast());
    } finally {
      calloc.free(ptr);
    }
  }

  /// Destroy an instance by handle.
  static void destroy(XLogInstance instance) {
    _b.xlog_destroy_instance(instance._handle);
  }

  /// Flush all log instances.
  static void flushAll({bool sync = false}) {
    _b.xlog_flush_all(sync ? 1 : 0);
  }
}
