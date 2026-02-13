# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Mars is a cross-platform infrastructure component developed by WeChat Mobile Team. It is a production-tested framework for mobile network communication, proven by billions of WeChat users.

**Core Components:**
- **comm**: Common library with socket, thread, message queue, coroutine utilities
- **xlog**: High-performance, reliable logging component
- **sdt**: Network detection/diagnostics component
- **stn**: Signaling network component (core networking layer)
- **app**: Application layer abstraction
- **baseevent**: Event handling for foreground/background, network changes
- **boot**: Component initialization and lifecycle management

## Build Commands

### Prerequisites
- Python 3.10 or higher required for all build scripts
- Platform-specific toolchains (see below)

### Windows
**Requirements:** Visual Studio 2022 (or VS 2019), CMake

**Environment Variables (REQUIRED):**
```bash
set MSVC_BIN_HOST64_PATH="C:/Program Files (x86)/Microsoft Visual Studio/2019/Professional/VC/Tools/MSVC/14.29.30133/bin/Hostx64/"
set MSVC_TOOLS_PATH="C:/Program Files (x86)/Microsoft Visual Studio/2019/Professional/Common7/Tools"
```

**Build Commands:**
```bash
cd mars
# Full mars library (Release)
python build_windows.py --mars --config Release

# Full mars library (Debug)
python build_windows.py --mars --config Debug

# Xlog only
python build_windows.py --xlog --config Release

# Generate Visual Studio project (for development)
python build_windows.py --gen_project

# Incremental build
python build_windows.py --mars --config Release --incremental True
```

**Output Location:** `mars/cmake_build/Windows/Windows.out/win/`
- `mars.lib` - merged static library
- PDB files in parent directory for debugging

### Android
**Requirements:** Android NDK r20+, Gradle

**Build Commands:**
```bash
cd mars
# Build native libraries
python build_android.py

# Or use Gradle
./gradlew build
```

**Gradle Integration:**
```gradle
dependencies {
    implementation 'com.tencent.mars:mars-core:1.2.5'  // Full Mars
    // or
    implementation 'com.tencent.mars:mars-xlog:1.2.5'  // Xlog only
    // or
    implementation 'com.tencent.mars:mars-wrapper:1.2.5'  // Wrapper for quick demos
}
```

### iOS/macOS
**Requirements:** Xcode, CMake

**Build Commands:**
```bash
cd mars
# iOS
python build_ios.py

# macOS
python build_osx.py

# watchOS
python build_watch.py
```

**Output:** `mars.framework` in build output directory

### Cross-Platform CMake
```bash
cd mars
mkdir cmake_build && cd cmake_build
cmake ..
cmake --build . --target install
```

## Architecture

### Component Dependencies
```
Application Code
    ↓
┌───────────────────────────────────┐
│  app (application callbacks)      │
├───────────────────────────────────┤
│  stn (network signaling)          │
│  sdt (network detection)          │
├───────────────────────────────────┤
│  baseevent (lifecycle events)     │
│  boot (component management)      │
├───────────────────────────────────┤
│  xlog (logging)                   │
│  comm (common utilities)          │
└───────────────────────────────────┘
```

### Key Architectural Concepts

**Task-Based Network Model:**
- Network requests are modeled as `Task` objects with taskid, cmdid, cgi path
- Tasks can use short link (HTTP), long link (persistent connection), or both
- Callbacks: `Req2Buf` (serialize request) → Network → `Buf2Resp` (parse response) → `OnTaskEnd` (completion)

**Long Link vs Short Link:**
- **Long Link**: Persistent TCP/QUIC connection for real-time signaling, push messages, low-latency requests
- **Short Link**: Traditional HTTP/HTTPS for one-off requests, uploads, downloads
- **Channel Selection**: Tasks specify `channel_select` (kChannelShort, kChannelLong, kChannelBoth)

**Multi-Process Safety:**
- Xlog supports multi-process logging - each process MUST use a separate log directory
- Never share log directories between processes

**Callback Architecture:**
- Components communicate via callback interfaces (mars::stn::Callback, mars::app::Callback)
- Callbacks must be set before initialization using `SetCallback()`
- Key callbacks: DNS resolution (OnNewDns), auth check (MakesureAuthed), request serialization (Req2Buf/Buf2Resp)

**Event-Driven Design:**
- baseevent layer handles: foreground/background changes (OnForeground), network changes (OnNetworkChange), account changes (requires StnLogic::reset())
- Components react to platform events for optimal battery and network efficiency

### Component Initialization Order

**Critical Sequence:**
1. `SetCallback()` - register all callbacks first
2. `Mars.init()` / `mars::baseevent::OnCreate()` - initialize Mars platform
3. Configure: `SetClientVersion()`, `SetLonglinkSvrAddr()`, `SetShortlinkSvrAddr()`
4. `OnForeground(true)` - set initial foreground state (default is background)
5. `MakesureLonglinkConnected()` - trigger connection

**Teardown:**
- `Mars.onDestroy()` / `mars::baseevent::OnDestroy()`
- `appender_close()` for xlog

### File Extensions
- `.rewriteme` files: These are template files that need `.rewriteme` extension removed and renamed to `.cc` when integrating into projects. They contain platform-specific callback implementations.

## Code Style

- **Indentation**: 4 spaces (not tabs)
- **Private functions**: Start with `__` (double underscore)
- **Function parameters**: Start with `_` (single underscore)
- Follow [Google C++ Style Guide](http://zh-google-styleguide.readthedocs.io/en/latest/google-cpp-styleguide/)

## Testing & Development

### Samples
Sample projects available in `samples/` directory:
- `samples/android/` - Android demo apps
- `samples/iOS/` - iOS demo apps
- `samples/Mac/` - macOS demo apps
- `samples/Windows/` - Windows demo apps

Each sample demonstrates initialization, xlog setup, STN usage, and task handling.

### Running Tests
Tests are embedded in source files (see `mars/comm/debugger/test_spy_sample.cc`). Use platform-specific test runners or build test targets from CMake.

## Common Workflows

### Adding a New Network Request (Task)
1. Define Task: Create `Task` with unique `taskid`, `cmdid`, `cgi` path, `channel_select`
2. Implement `Req2Buf`: Serialize request data to `AutoBuffer`
3. Implement `Buf2Resp`: Deserialize response from `AutoBuffer`, return error code
4. Implement `OnTaskEnd`: Handle completion (success/failure/timeout)
5. Submit Task: `StartTask(task)` via STN API

### Debugging Network Issues
- Enable xlog console output: `appender_set_console_log(true)` and `xlogger_SetLevel(kLevelDebug)`
- Check xlog files in configured log directory
- Monitor callbacks: `ReportConnectStatus`, `OnLongLinkNetworkError`, `OnShortLinkNetworkError`
- Use SDT component for network diagnostics

### Modifying Encryption/Packing
- Long link encoder: Implement custom `LongLinkEncoder` interface, register via `LonglinkConfig`
- Short link: Customize in `Req2Buf`/`Buf2Resp` callbacks
- Xlog encryption: Provide `pub_key` in `XLogConfig` for public key encryption

## Platform-Specific Notes

**Android:**
- Load native libraries: `System.loadLibrary("c++_shared")` then `System.loadLibrary("marsxlog")`/`System.loadLibrary("marsstn")`
- Use cache directory for xlog to avoid SIGBUS: `cachedir = getFilesDir() + "/xlog"`
- Multi-process: Each process needs separate log file via unique `nameprefix`

**iOS/macOS:**
- Disable backup for log directory using `setxattr` with `com.apple.MobileBackup`
- Bridge C++ callbacks to Objective-C using wrapper classes

**Windows:**
- Ensure OpenSSL libraries are linked: `openssl/openssl_lib_windows/x86/libcrypto.lib` and `libssl.lib`
- lib.exe path must be configured for merging static libraries

## Branch & Contribution Workflow

- **master**: Release branch (tags: 1.1.0, 1.2.0, ...) - DO NOT submit PRs here
- **develop**: Active development branch - submit feature/bugfix PRs here
- **hotfix**: Emergency fixes for released versions - only for urgent production issues

See [CONTRIBUTING.md](CONTRIBUTING.md) for detailed contribution guidelines.

## Important Security Notes

- Never commit log files containing sensitive data
- Use dedicated directories for xlog (files may be auto-deleted)
- Avoid storing credentials in code - use secure storage mechanisms
- Xlog supports encryption via public key configuration
