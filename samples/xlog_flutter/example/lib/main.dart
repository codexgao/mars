import 'dart:io';

import 'package:flutter/material.dart';
import 'package:xlog_flutter/xlog_flutter.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  runApp(const XLogTestApp());
}

class XLogTestApp extends StatelessWidget {
  const XLogTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'xlog_flutter Test',
      theme: ThemeData(
        colorSchemeSeed: Colors.blue,
        useMaterial3: true,
      ),
      home: const XLogTestPage(),
    );
  }
}

class XLogTestPage extends StatefulWidget {
  const XLogTestPage({super.key});

  @override
  State<XLogTestPage> createState() => _XLogTestPageState();
}

class _XLogTestPageState extends State<XLogTestPage> {
  final List<String> _logs = [];
  XLogInstance? _instance;
  String _logDir = '';
  bool _initialized = false;
  bool _instanceOpen = false;
  XLogLevel _selectedLevel = XLogLevel.debug;

  void _addLog(String message) {
    setState(() {
      _logs.add('[${DateTime.now().toIso8601String().substring(11, 19)}] $message');
      // Keep last 50 entries
      if (_logs.length > 50) _logs.removeAt(0);
    });
  }

  Future<void> _initialize() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      _logDir = '${appDir.path}${Platform.pathSeparator}xlog_test';

      // Ensure log directory exists
      final dir = Directory(_logDir);
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }

      setState(() => _initialized = true);
      _addLog('OK: Ready');
      _addLog('Log dir: $_logDir');
    } catch (e) {
      _addLog('ERROR: $e');
    }
  }

  void _openInstance() {
    try {
      /**
      save private key
03e08451c97a2388625c636bc8459a1857cc2c40f6d51554808befb363415a30

appender_open's parameter:
5785f0bd2b145d6fb3acba287cabfdbb96ed6053679ef7b7e0c77ff134f2a86776fe93e77fbed209a93e9165556be8f2d65b6be730da6529e8533643a657e5b1
       */
      final config = XLogConfig(
        logdir: _logDir,
        nameprefix: 'test',
        mode: XLogAppenderMode.async_,
        compressMode: XLogCompressMode.zstd,
        pubKey:
            '5785f0bd2b145d6fb3acba287cabfdbb96ed6053679ef7b7e0c77ff134f2a86776fe93e77fbed209a93e9165556be8f2d65b6be730da6529e8533643a657e5b1',
      );
      _instance = XLog.open(config, level: _selectedLevel);
      _instance!.consoleLogOpen = true;

      setState(() => _instanceOpen = _instance!.isValid);
      _addLog('OK: Instance opened (handle=${_instance!.handle})');
    } catch (e) {
      _addLog('ERROR: $e');
    }
  }

  void _closeInstance() {
    try {
      XLog.release('test');
      setState(() {
        _instanceOpen = false;
        _instance = null;
      });
      _addLog('OK: Instance released');
    } catch (e) {
      _addLog('ERROR: $e');
    }
  }

  void _writeLog(XLogLevel level, String levelName) {
    if (_instance == null || !_instance!.isValid) {
      _addLog('WARN: No open instance');
      return;
    }
    try {
      _instance!.write(level, 'TestTag', '[$levelName] Hello from xlog_flutter! (${DateTime.now()})');
      _addLog('OK: Wrote $levelName log');
    } catch (e) {
      _addLog('ERROR: $e');
    }
  }

  void _flush({bool sync = false}) {
    if (_instance == null) {
      _addLog('WARN: No open instance');
      return;
    }
    try {
      _instance!.flush(sync: sync);
      _addLog('OK: Flushed (sync=$sync)');
    } catch (e) {
      _addLog('ERROR: $e');
    }
  }

  void _flushAll({bool sync = false}) {
    try {
      XLog.flushAll(sync: sync);
      _addLog('OK: FlushAll (sync=$sync)');
    } catch (e) {
      _addLog('ERROR: $e');
    }
  }

  void _getLogPath() {
    if (_instance == null) {
      _addLog('WARN: No open instance');
      return;
    }
    try {
      final path = _instance!.logPath;
      _addLog('Log path: ${path ?? "(null)"}');
    } catch (e) {
      _addLog('ERROR: $e');
    }
  }

  void _checkHasInstance() {
    try {
      final exists = XLog.has('test');
      _addLog('has("test") = $exists');
    } catch (e) {
      _addLog('ERROR: $e');
    }
  }

  void _toggleConsole() {
    if (_instance == null) return;
    try {
      _instance!.consoleLogOpen = true;
      _addLog('OK: Console log enabled');
    } catch (e) {
      _addLog('ERROR: $e');
    }
  }

  void _setLevel(XLogLevel level) {
    setState(() => _selectedLevel = level);
    if (_instance != null && _instance!.isValid) {
      _instance!.level = level;
      _addLog('OK: Level set to ${level.name}');
    }
  }

  void _checkEnabledLevels() {
    if (_instance == null) return;
    final results = XLogLevel.values
        .where((l) => l != XLogLevel.all && l != XLogLevel.none)
        .map((l) => '${l.name}=${_instance!.isEnabledFor(l) ? "Y" : "N"}')
        .join(' ');
    _addLog('Enabled: $results');
  }

  void _listLogFiles() {
    try {
      final dir = Directory(_logDir);
      if (!dir.existsSync()) {
        _addLog('Log dir does not exist');
        return;
      }
      final files = dir.listSync().map((f) => f.path.split(Platform.pathSeparator).last).toList();
      if (files.isEmpty) {
        _addLog('No files in log dir');
      } else {
        for (final f in files) {
          _addLog('  $f');
        }
      }
    } catch (e) {
      _addLog('ERROR: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('xlog_flutter Test'),
        actions: [
          IconButton(
            onPressed: () => setState(() => _logs.clear()),
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear log',
          ),
        ],
      ),
      body: Column(
        children: [
          // Status bar
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: _instanceOpen ? Colors.green.shade50 : Colors.grey.shade100,
            child: Text(
              _instanceOpen
                  ? 'Instance: open (handle=${_instance!.handle}, level=${_selectedLevel.name})'
                  : _initialized
                      ? 'Initialized — no instance open'
                      : 'Not initialized',
              style: TextStyle(
                fontFamily: 'monospace',
                color: _instanceOpen ? Colors.green.shade900 : Colors.grey.shade700,
              ),
            ),
          ),

          // Controls
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                // Lifecycle
                _btn('Initialize', _initialized ? null : _initialize),
                _btn('Open', (!_initialized || _instanceOpen) ? null : _openInstance),
                _btn('Close', _instanceOpen ? _closeInstance : null),
                _btn('Has?', _initialized ? _checkHasInstance : null),

                const SizedBox(width: 8),

                // Write
                _btn('Verbose', _instanceOpen ? () => _writeLog(XLogLevel.verbose, 'VERBOSE') : null),
                _btn('Debug', _instanceOpen ? () => _writeLog(XLogLevel.debug, 'DEBUG') : null),
                _btn('Info', _instanceOpen ? () => _writeLog(XLogLevel.info, 'INFO') : null),
                _btn('Warn', _instanceOpen ? () => _writeLog(XLogLevel.warn, 'WARN') : null),
                _btn('Error', _instanceOpen ? () => _writeLog(XLogLevel.error, 'ERROR') : null),
                _btn('Fatal', _instanceOpen ? () => _writeLog(XLogLevel.fatal, 'FATAL') : null),

                const SizedBox(width: 8),

                // Control
                _btn('Flush', _instanceOpen ? () => _flush() : null),
                _btn('Flush Sync', _instanceOpen ? () => _flush(sync: true) : null),
                _btn('FlushAll', _initialized ? () => _flushAll(sync: true) : null),
                _btn('Console On', _instanceOpen ? _toggleConsole : null),
                _btn('Log Path', _instanceOpen ? _getLogPath : null),
                _btn('Enabled?', _instanceOpen ? _checkEnabledLevels : null),
                _btn('List Files', _initialized ? _listLogFiles : null),

                const SizedBox(width: 8),

                // Level selector
                DropdownButton<XLogLevel>(
                  value: _selectedLevel,
                  onChanged: (v) {
                    if (v != null) _setLevel(v);
                  },
                  items: XLogLevel.values
                      .where((l) => l != XLogLevel.all)
                      .map((l) => DropdownMenuItem(value: l, child: Text(l.name)))
                      .toList(),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Log output
          Expanded(
            child: Container(
              color: Colors.grey.shade900,
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              child: SelectableText(
                _logs.isEmpty ? '(no output)' : _logs.join('\n'),
                style: const TextStyle(
                  fontFamily: 'Consolas',
                  fontSize: 12,
                  color: Colors.greenAccent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _btn(String label, VoidCallback? onPressed) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        minimumSize: Size.zero,
      ),
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }
}
