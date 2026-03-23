# xlog_flutter

Flutter FFI plugin for [Mars xlog](https://github.com/Tencent/mars) - a high-performance, reliable logging library from WeChat.

## Features

- Multi-instance logging with independent configurations
- High performance with async writing
- Compression support (Zlib, Zstandard)
- Encryption support (ECC + TEA)
- Multi-process safe
- Cross-platform: Android, iOS, Windows, macOS, Linux

## Getting Started

### 1. Build xlog Native Library

Before using this plugin, you need to build the xlog native library for your target platform.

#### Android

```bash
# Set NDK environment variable
export NDK_ROOT=/path/to/android-ndk  # Linux/macOS
set NDK_ROOT=D:\Android\Sdk\ndk\25.x.x  # Windows

# Build for Android
cd mars/xlog
# Release: stripped .so + .debug symbols
python build_android.py --config Release --output-dir ../../samples/xlog_flutter/android/src/main/jniLibs --arch armeabi-v7a arm64-v8a
# Debug: unstripped .so
python build_android.py --config Debug --output-dir ../../samples/xlog_flutter/android/src/debug/jniLibs --arch armeabi-v7a arm64-v8a
```

Release output is written to `src/main/jniLibs`, and Debug output is written to `src/debug/jniLibs`.

#### Windows

```bash
# Set Visual Studio environment
set MSVC_TOOLS_PATH=D:\Program Files\Microsoft Visual Studio\2022\Professional\Common7\Tools

cd mars/xlog
python build_windows.py --config Release
```

The output will be in `mars/xlog/build/windows/Release/`.

### 2. Add Dependency

Add to your `pubspec.yaml`:

```yaml
dependencies:
  xlog_flutter:
    path: ../samples/xlog_flutter
```

### 3. Usage

```dart
import 'package:xlog_flutter/xlog_flutter.dart';

// Initialize (auto-loads native library)
XLog.initialize();

// Open an instance
final instance = XLog.open(XLogConfig(
  logdir: '/path/to/logs',
  nameprefix: 'myapp',
  mode: XLogAppenderMode.async_,
  compressMode: XLogCompressMode.zstd,
));

// Write logs
instance.debug('TAG', 'Debug message');
instance.info('TAG', 'Info message');
instance.error('TAG', 'Error message');

// Flush before exit
instance.flush(sync: true);

// Release instance
XLog.release('myapp');
```

## Platform-Specific Notes

### Android

1. Each process must use a unique `nameprefix`
2. Use `getFilesDir()` for log directory to avoid SIGBUS issues
3. `libc++_shared.so` is included automatically

### iOS

1. Log directory should be marked as "do not backup"
2. Link `mars.framework` in your Xcode project

### Windows

1. Place `xlog.dll` in the same directory as your executable
2. Requires Visual C++ Redistributable

## Configuration Options

| Option | Description | Default |
|--------|-------------|---------|
| `logdir` | Log output directory (required) | - |
| `nameprefix` | Instance identifier (required) | - |
| `mode` | Async or sync writing | `async_` |
| `pubKey` | Encryption public key (optional) | `null` |
| `compressMode` | Zlib or Zstd compression | `zlib` |
| `compressLevel` | Compression level (0-9) | `0` |
| `cachedir` | Cache directory (optional) | `null` |
| `cacheDays` | Cache retention days | `0` |

## Building from Source

### Prerequisites

- Python 3.10+
- CMake 3.10+
- NDK r20+ (for Android)
- Visual Studio 2022 (for Windows)
- Xcode 14+ (for iOS/macOS)

### Build Commands

```bash
# Android (output to default build directory)
python mars/xlog/build_android.py --arch armeabi-v7a arm64-v8a

# Android (output to custom directory)
python mars/xlog/build_android.py --output-dir ./output --arch armeabi-v7a arm64-v8a

# Windows
python mars/xlog/build_windows.py --config Release

# iOS (TODO)
python mars/xlog/build_ios.py
```

## Output Structure

### Android (`build_android.py --output-dir`)

```
samples/xlog_flutter/android/src/main/jniLibs/
├── armeabi-v7a/
│   ├── libxlog.so          # stripped
│   └── libc++_shared.so
├── arm64-v8a/
│   ├── libxlog.so          # stripped
│   └── libc++_shared.so
└── symbols/                # debug symbols for Release
    ├── armeabi-v7a/
    │   └── libxlog.so.debug
    └── arm64-v8a/
        └── libxlog.so.debug

samples/xlog_flutter/android/src/debug/jniLibs/
├── armeabi-v7a/
│   ├── libxlog.so          # unstripped
│   └── libc++_shared.so
└── arm64-v8a/
    ├── libxlog.so          # unstripped
    └── libc++_shared.so
```

### Windows (`build_windows.py`)

```
mars/xlog/build/windows/
├── Release/
│   ├── xlog.dll
│   ├── xlog.lib
│   └── xlog.pdb
└── include/
    └── ...
```

## License

MIT License - same as Mars project.
