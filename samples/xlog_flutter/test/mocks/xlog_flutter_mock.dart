import 'package:mockito/mockito.dart';

/// XLog 模拟库供测试使用
///
/// 这些模拟对象可以用于单元测试，以避免依赖真实的原生库

/// 模拟配置变更监听器
class MockConfigChangeListener extends Mock {
  void onConfigChanged(Map<String, dynamic> config) {}
}

/// 模拟日志输出监听器
class MockLogListener extends Mock {
  void onLogWritten(String level, String tag, String message) {}
}

/// 模拟文件操作监听器
class MockFileOperationListener extends Mock {
  void onFileCreated(String fileName) {}
  void onFileRotated(String oldFileName, String newFileName) {}
  void onFileFlushed(String fileName) {}
}

/// 模拟原生库操作追踪器
class NativeOperationTracker {
  final List<String> operations = [];
  final Map<String, int> operationCounts = {};

  void recordOperation(String operationName, [Map<String, dynamic>? params]) {
    operations.add('$operationName${params != null ? ':$params' : ''}');
    operationCounts[operationName] = (operationCounts[operationName] ?? 0) + 1;
  }

  void reset() {
    operations.clear();
    operationCounts.clear();
  }

  int getOperationCount(String operationName) =>
      operationCounts[operationName] ?? 0;

  bool hasOperation(String operationName) =>
      operationCounts.containsKey(operationName);

  List<String> getOperationsSince(int index) {
    if (index >= operations.length) return [];
    return operations.sublist(index);
  }
}

/// 模拟日志缓冲区
class MockLogBuffer {
  final List<LogEntry> _entries = [];

  void write(int level, String tag, String message) {
    _entries.add(LogEntry(
      level: level,
      tag: tag,
      message: message,
      timestamp: DateTime.now(),
    ));
  }

  List<LogEntry> getEntries() => List.unmodifiable(_entries);

  List<LogEntry> getEntriesByTag(String tag) =>
      _entries.where((e) => e.tag == tag).toList();

  List<LogEntry> getEntriesByLevel(int level) =>
      _entries.where((e) => e.level == level).toList();

  int getEntryCount() => _entries.length;

  void clear() => _entries.clear();

  String getAllAsString() {
    return _entries
        .map((e) => '[${LogLevelHelper.getName(e.level)}] ${e.tag}: ${e.message}')
        .join('\n');
  }
}

/// 日志条目模型
class LogEntry {
  final int level;
  final String tag;
  final String message;
  final DateTime timestamp;

  LogEntry({
    required this.level,
    required this.tag,
    required this.message,
    required this.timestamp,
  });

  @override
  String toString() =>
      'LogEntry(level=$level, tag=$tag, message=$message, time=$timestamp)';
}

/// 日志级别帮助器
class LogLevelHelper {
  static const Map<int, String> _levelNames = {
    0: 'VERBOSE',
    1: 'DEBUG',
    2: 'INFO',
    3: 'WARN',
    4: 'ERROR',
    5: 'FATAL',
    6: 'NONE',
  };

  static String getName(int level) => _levelNames[level] ?? 'UNKNOWN';

  static int getValue(String name) {
    for (final entry in _levelNames.entries) {
      if (entry.value == name) return entry.key;
    }
    return -1;
  }
}

/// 模拟配置构建器
class MockConfigBuilder {
  String logDir = '/tmp/logs';
  String namePrefix = 'test_app';
  int level = 1; // DEBUG
  int mode = 0; // ASYNC
  int compressMode = 0; // ZLIB
  String pubKey = '';
  String cacheDir = '';
  int cacheDays = 0;

  MockConfigBuilder withLogDir(String dir) {
    logDir = dir;
    return this;
  }

  MockConfigBuilder withNamePrefix(String prefix) {
    namePrefix = prefix;
    return this;
  }

  MockConfigBuilder withLevel(int lvl) {
    level = lvl;
    return this;
  }

  MockConfigBuilder withMode(int m) {
    mode = m;
    return this;
  }

  MockConfigBuilder withCompressMode(int cm) {
    compressMode = cm;
    return this;
  }

  MockConfigBuilder withPubKey(String key) {
    pubKey = key;
    return this;
  }

  MockConfigBuilder withCacheDir(String dir) {
    cacheDir = dir;
    return this;
  }

  MockConfigBuilder withCacheDays(int days) {
    cacheDays = days;
    return this;
  }

  Map<String, dynamic> build() {
    return {
      'logDir': logDir,
      'namePrefix': namePrefix,
      'level': level,
      'mode': mode,
      'compressMode': compressMode,
      'pubKey': pubKey,
      'cacheDir': cacheDir,
      'cacheDays': cacheDays,
    };
  }
}

/// 测试夹具
class TestFixture {
  late MockLogBuffer logBuffer;
  late NativeOperationTracker operationTracker;
  late MockConfigChangeListener configListener;
  late MockLogListener logListener;
  late MockFileOperationListener fileListener;

  void setUp() {
    logBuffer = MockLogBuffer();
    operationTracker = NativeOperationTracker();
    configListener = MockConfigChangeListener();
    logListener = MockLogListener();
    fileListener = MockFileOperationListener();
  }

  void tearDown() {
    logBuffer.clear();
    operationTracker.reset();
  }
}

/// 模拟时间控制器
class MockTimeController {
  DateTime _currentTime = DateTime.now();

  DateTime getCurrentTime() => _currentTime;

  void setCurrentTime(DateTime time) {
    _currentTime = time;
  }

  void advanceBySeconds(int seconds) {
    _currentTime = _currentTime.add(Duration(seconds: seconds));
  }

  void advanceByMinutes(int minutes) {
    _currentTime = _currentTime.add(Duration(minutes: minutes));
  }

  void advanceByHours(int hours) {
    _currentTime = _currentTime.add(Duration(hours: hours));
  }

  void advanceByDays(int days) {
    _currentTime = _currentTime.add(Duration(days: days));
  }

  void reset() {
    _currentTime = DateTime.now();
  }
}

/// 模拟文件系统
class MockFileSystem {
  final Map<String, MockFile> _files = {};

  MockFile createFile(String path, String content) {
    final file = MockFile(path, content);
    _files[path] = file;
    return file;
  }

  MockFile? getFile(String path) => _files[path];

  bool fileExists(String path) => _files.containsKey(path);

  void deleteFile(String path) => _files.remove(path);

  List<String> listFiles() => _files.keys.toList();

  int getTotalSize() {
    int total = 0;
    for (final file in _files.values) {
      total += file.size;
    }
    return total;
  }

  void clear() => _files.clear();
}

/// 模拟文件
class MockFile {
  final String path;
  late String _content;
  DateTime _createdTime = DateTime.now();
  DateTime _modifiedTime = DateTime.now();

  MockFile(this.path, String content) : _content = content;

  String get content => _content;
  int get size => _content.length;
  DateTime get createdTime => _createdTime;
  DateTime get modifiedTime => _modifiedTime;

  void write(String content) {
    _content = content;
    _modifiedTime = DateTime.now();
  }

  void append(String content) {
    _content += content;
    _modifiedTime = DateTime.now();
  }

  void setCreatedTime(DateTime time) => _createdTime = time;
  void setModifiedTime(DateTime time) => _modifiedTime = time;

  @override
  String toString() => 'MockFile($path, size=$size)';
}

/// 模拟配置验证器
class ConfigValidator {
  static bool isValidLogDir(String dir) {
    return dir.isNotEmpty && (dir.startsWith('/') || dir.startsWith('./') || dir.contains(':'));
  }

  static bool isValidNamePrefix(String prefix) {
    return prefix.isNotEmpty && RegExp(r'^[a-zA-Z0-9_\-\.]+$').hasMatch(prefix);
  }

  static bool isValidLevel(int level) {
    return level >= 0 && level <= 6;
  }

  static bool isValidMode(int mode) {
    return mode == 0 || mode == 1;
  }

  static bool isValidCompressMode(int compressMode) {
    return compressMode == 0 || compressMode == 1;
  }

  static bool isValidPubKey(String pubKey) {
    if (pubKey.isEmpty) return true; // 空表示禁用加密
    return RegExp(r'^[a-fA-F0-9]*$').hasMatch(pubKey) && pubKey.length % 2 == 0;
  }

  static bool isValidCacheDays(int days) {
    return days >= 0 && days <= 36500; // Up to 100 years
  }

  static List<String> validate(Map<String, dynamic> config) {
    final errors = <String>[];

    if (!isValidLogDir(config['logDir'] ?? '')) {
      errors.add('Invalid logDir');
    }
    if (!isValidNamePrefix(config['namePrefix'] ?? '')) {
      errors.add('Invalid namePrefix');
    }
    if (!isValidLevel(config['level'] ?? 0)) {
      errors.add('Invalid level');
    }
    if (!isValidMode(config['mode'] ?? 0)) {
      errors.add('Invalid mode');
    }
    if (!isValidCompressMode(config['compressMode'] ?? 0)) {
      errors.add('Invalid compressMode');
    }
    if (!isValidPubKey(config['pubKey'] ?? '')) {
      errors.add('Invalid pubKey');
    }
    if (!isValidCacheDays(config['cacheDays'] ?? 0)) {
      errors.add('Invalid cacheDays');
    }

    return errors;
  }

  static bool isConfigValid(Map<String, dynamic> config) {
    return validate(config).isEmpty;
  }
}

/// 测试数据生成器
class TestDataGenerator {
  static String generateRandomTag({int length = 10}) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = <int>[];
    for (int i = 0; i < length; i++) {
      random.add(DateTime.now().millisecond % chars.length);
    }
    return random.map((i) => chars[i]).join();
  }

  static String generateRandomMessage({int length = 100}) {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 \n';
    final random = <int>[];
    for (int i = 0; i < length; i++) {
      random.add((DateTime.now().millisecond + i) % chars.length);
    }
    return random.map((i) => chars[i]).join();
  }

  static List<LogEntry> generateLogEntries(int count) {
    final entries = <LogEntry>[];
    for (int i = 0; i < count; i++) {
      entries.add(LogEntry(
        level: i % 7,
        tag: 'tag_$i',
        message: 'message_$i',
        timestamp: DateTime.now().add(Duration(milliseconds: i)),
      ));
    }
    return entries;
  }
}
