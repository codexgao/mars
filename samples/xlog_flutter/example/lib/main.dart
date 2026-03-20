import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:xlog_flutter/xlog_flutter.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String _status = 'Not initialized';
  bool _opened = false;

  Future<void> _openXlog() async {
    final dir = await getApplicationSupportDirectory();
    final logDir = Directory('${dir.path}/xlog');
    print('Log directory: ${logDir.path}');
    await logDir.create(recursive: true);

    XLog.open(XLogConfig(
      logDir: logDir.path,
      namePrefix: 'xlog_flutter_demo',
      level: LogLevel.verbose,
      mode: AppenderMode.async_,
      pubKey:
          '99dbfea8e185e61f183c0d52547392aba065d4df3a8c3ea2647020e01fc09818ed5073adcb020b09282778477934b469c8aeba7b05698518af0b318ebbe3ef2d',
    ));
    XLog.setConsoleLog(true);

    setState(() {
      _opened = true;
      _status = 'Opened. Log dir: ${logDir.path}';
    });
  }

  void _writeLogs() {
    if (!_opened) return;
    XLog.verbose('Demo', 'This is a verbose log');
    XLog.debug('Demo', 'This is a debug log');
    XLog.info('Demo', 'This is an info log');
    XLog.warn('Demo', 'This is a warning log');
    XLog.error('Demo', 'This is an error log');
    setState(() => _status = 'Wrote 5 log entries.');
  }

  void _flush() {
    if (!_opened) return;
    XLog.flushSync();
    setState(() => _status = 'Flushed to disk.');
  }

  void _close() {
    if (!_opened) return;
    XLog.close();
    setState(() {
      _opened = false;
      _status = 'Closed.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('xlog_flutter Demo')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(_status, style: const TextStyle(fontSize: 14)),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _openXlog, child: const Text('Open XLog')),
              ElevatedButton(onPressed: _writeLogs, child: const Text('Write Logs')),
              ElevatedButton(onPressed: _flush, child: const Text('Flush Sync')),
              ElevatedButton(onPressed: _close, child: const Text('Close XLog')),
            ],
          ),
        ),
      ),
    );
  }
}
