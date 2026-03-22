# Xlog Multi-Instance Refactor Design

## Overview

Refactor the xlog module from a "global singleton + optional multi-instance" model to a pure multi-instance model. All log operations go through `NewXloggerInstance()`. The old `appender_open()` global API is deprecated and replaced with a backward-compatible wrapper.

## Requirements

- **Single process, multiple log files**: different business modules (network, database, UI, etc.) write to separate files with independent configurations.
- **Each instance fully independent**: mode (sync/async), logdir, nameprefix, pub_key, compress_mode, compress_level, cachedir, cache_days all independently configurable per instance.
- **Unified internal implementation**: `appender_open()` becomes a wrapper around `NewXloggerInstance()` internally, creating a "default" named instance.
- **Full platform support**: C++ core + Android JNI + iOS Objective-C wrappers.
- **Backward compatibility**: deprecated wrappers for old global APIs so existing callers compile with warnings.

## Architecture

### Current Model

```
sg_default_appender (global singleton)   <- appender_open()
         +
map<nameprefix, XloggerCategory*>        <- NewXloggerInstance()
```

### New Model

```
map<nameprefix, XloggerCategory*>        <- NewXloggerInstance() only
  "default" is a normal instance
  "network" is a normal instance
  "database" is a normal instance
  ...
```

### Instance Lifecycle

```
Create:
  NewXloggerInstance(XLogConfig, level)
    -> XloggerAppender::NewInstance(config)
    -> XloggerCategory::NewInstance(appender_ptr, write_func)
    -> register in global map by nameprefix
    -> return uintptr_t

Use:
  XloggerWrite(instance_ptr, info, log)
    -> cast to XloggerCategory*
    -> category->Write(info, log)

Destroy:
  ReleaseXloggerInstance(nameprefix) or DestroyXlogInstance(instance_ptr)
    -> appender->Close()
    -> 5-second delayed release
    -> remove from map
```

## C++ API Design (xlogger_interface.h)

### Core API (retained/enhanced)

```cpp
namespace mars {
namespace xlog {

// Create a new xlog instance with full independent config.
// Returns uintptr_t (cast from XloggerCategory*), 0 on failure.
uintptr_t NewXloggerInstance(const XLogConfig& _config, TLogLevel _level = kLevelInfo);

// Get existing instance by nameprefix.
uintptr_t GetXloggerInstance(const char* _nameprefix);

// Destroy instance by nameprefix.
void ReleaseXloggerInstance(const char* _nameprefix);

// Destroy instance by handle.
void DestroyXlogInstance(uintptr_t _instance);

// Check if instance exists.
bool HasXlogInstance(const char* _nameprefix);

// Get all active instance nameprefixes.
std::vector<std::string> GetAllXlogInstanceNames();

// ===== Write =====
void XloggerWrite(uintptr_t _instance, const XLoggerInfo* _info, const char* _log);

// ===== Query =====
TLogLevel GetLevel(uintptr_t _instance);
bool IsEnabledFor(uintptr_t _instance, TLogLevel _level);

// ===== Config =====
void SetLevel(uintptr_t _instance, TLogLevel _level);
void SetAppenderMode(uintptr_t _instance, TAppenderMode _mode);
void SetConsoleLogOpen(uintptr_t _instance, bool _is_open);
void SetMaxFileSize(uintptr_t _instance, long _max_file_size);
void SetMaxAliveTime(uintptr_t _instance, long _alive_seconds);

// ===== Flush =====
void Flush(uintptr_t _instance, bool _is_sync = false);
void FlushAll(bool _is_sync = false);

}  // namespace xlog
}  // namespace mars
```

### Return type change

Currently `NewXloggerInstance()` returns `mars::comm::XloggerCategory*`. It will be changed to return `uintptr_t` for consistency with all other instance-based APIs and to simplify cross-language interop (Java long, OC uint64_t).

### New APIs

| Function | Purpose |
|----------|---------|
| `DestroyXlogInstance(uintptr_t)` | Destroy by handle (reverse lookup nameprefix from map) |
| `HasXlogInstance(const char*)` | Check existence without acquiring instance |
| `GetAllXlogInstanceNames()` | List all active instances |

### Deprecated Compatibility Wrappers (appender.h)

```cpp
namespace mars {
namespace xlog {

// All marked __attribute__((deprecated))

inline void appender_open(const XLogConfig& _config) {
    NewXloggerInstance(_config, kLevelInfo);
}

inline void appender_close() {
    ReleaseXloggerInstance("default");
}

inline void appender_flush() {
    FlushAll(false);
}

inline void appender_flush_sync() {
    FlushAll(true);
}

inline void appender_setmode(TAppenderMode _mode) {
    uintptr_t inst = GetXloggerInstance("default");
    if (inst) SetAppenderMode(inst, _mode);
}

inline void appender_set_console_log_open(bool _is_open) {
    uintptr_t inst = GetXloggerInstance("default");
    if (inst) SetConsoleLogOpen(inst, _is_open);
}

inline void appender_set_max_file_size(uint64_t _max_byte_size) {
    uintptr_t inst = GetXloggerInstance("default");
    if (inst) SetMaxFileSize(inst, _max_byte_size);
}

inline void appender_set_max_alive_duration(long _max_time) {
    uintptr_t inst = GetXloggerInstance("default");
    if (inst) SetMaxAliveTime(inst, _max_time);
}

}  // namespace xlog
}  // namespace mars
```

These wrappers assume `nameprefix_ = "default"` in the XLogConfig passed to `appender_open()`. If the caller uses a different nameprefix, `appender_close()` will not find the instance. This is a known limitation of the compatibility layer; callers should migrate to the new API.

## Internal Implementation Changes

### appender.cc changes

**Remove:**
- `sg_default_appender` global pointer (line ~1276)
- `sg_release_guard` flag (line ~1277)
- `sg_default_console_log_open` flag (line ~1278)
- `sg_mutex` global mutex (line ~1279)
- `sg_max_byte_size` / `sg_max_alive_time` globals (line ~1280-1281)
- `xlogger_appender()` global callback function (line ~1298)
- `appender_open()` / `appender_close()` implementations (line ~1289-1340)
- `appender_flush()` / `appender_flush_sync()` implementations
- `appender_setmode()` / `appender_set_console_log_open()` implementations
- `appender_set_max_file_size()` / `appender_set_max_alive_duration()` implementations

**Keep:**
- `XloggerAppender` class and all its methods (Open, Close, Write, Flush, etc.)
- `ConsoleLog()` function
- All file management logic (__Log2File, __OpenLogFile, etc.)
- All buffer/compression logic
- `g_log_write_callback` (optional extensibility hook)

### xlogger_interface.cc changes

**Modify `NewXloggerInstance()`:**
- Change return type from `XloggerCategory*` to `uintptr_t`
- If `_instance_ptr == 0` in any API, no longer fall through to global `xlogger_*` functions. Instead return error / no-op.

**Add `DestroyXlogInstance(uintptr_t)`:**
```cpp
void DestroyXlogInstance(uintptr_t _instance) {
    if (0 == _instance) return;
    ScopedLock lock(GetGlobalMutex());
    auto& xmap = GetGlobalInstanceMap();
    for (auto it = xmap.begin(); it != xmap.end(); ++it) {
        if (reinterpret_cast<uintptr_t>(it->second) == _instance) {
            XloggerCategory* category = it->second;
            XloggerAppender* appender = reinterpret_cast<XloggerAppender*>(category->GetAppender());
            appender->Close();
            XloggerAppender::DelayRelease(appender);
            XloggerCategory::DelayRelease(category);
            xmap.erase(it);
            return;
        }
    }
}
```

**Add `HasXlogInstance()` and `GetAllXlogInstanceNames()`:**
```cpp
bool HasXlogInstance(const char* _nameprefix) {
    if (nullptr == _nameprefix) return false;
    ScopedLock lock(GetGlobalMutex());
    return GetGlobalInstanceMap().count(_nameprefix) > 0;
}

std::vector<std::string> GetAllXlogInstanceNames() {
    ScopedLock lock(GetGlobalMutex());
    std::vector<std::string> names;
    for (const auto& pair : GetGlobalInstanceMap()) {
        names.push_back(pair.first);
    }
    return names;
}
```

**Modify `FlushAll()`:**
- Remove the call to global `appender_flush()` / `appender_flush_sync()`
- Only iterate the instance map (all instances including "default" are in the map now)

```cpp
void FlushAll(bool _is_sync) {
    ScopedLock lock(GetGlobalMutex());
    auto& xmap = GetGlobalInstanceMap();
    for (auto it = xmap.begin(); it != xmap.end(); ++it) {
        XloggerCategory* category = it->second;
        XloggerAppender* appender = reinterpret_cast<XloggerAppender*>(category->GetAppender());
        _is_sync ? appender->FlushSync() : appender->Flush();
    }
}
```

**Modify all `_instance_ptr == 0` branches:**
- Current behavior: fall through to global `xlogger_SetLevel()`, `xlogger_Write()`, etc.
- New behavior: return early / no-op when `_instance_ptr == 0` (no global instance exists)
- Alternative: treat 0 as "default" instance by looking up `GetXloggerInstance("default")`

Decision: When `_instance_ptr == 0`, look up the "default" instance from the map. This preserves backward compatibility for callers that pass 0 expecting global behavior.

```cpp
static uintptr_t ResolveInstance(uintptr_t _instance_ptr) {
    if (0 != _instance_ptr) return _instance_ptr;
    auto* cat = GetGlobalInstanceMap()["default"];  // may be nullptr
    return reinterpret_cast<uintptr_t>(cat);
}
```

## Android JNI Changes (Java2C_Xlog.cc)

### Modified JNI functions

| JNI Function | Change |
|-------------|--------|
| `newXlogInstance` | Rename to match `NewXloggerInstance`, return `jlong` (unchanged) |
| `getXlogInstance` | Return `jlong` from `GetXloggerInstance()` (unchanged behavior) |
| `releaseXlogInstance` | Unchanged |
| `logWrite2` | Unchanged (already uses `_log_instance_ptr`) |
| `getLogLevel` | Unchanged |
| `setLogLevel` | Unchanged |
| `setAppenderMode` | Unchanged |
| `setConsoleLogOpen` | Unchanged |
| `setMaxFileSize` | Unchanged |
| `setMaxAliveTime` | Unchanged |

### New JNI functions

```cpp
JNIEXPORT void JNICALL Java_com_tencent_mars_xlog_Xlog_destroyXlogInstance(
    JNIEnv* env, jobject, jlong _instance_ptr) {
    mars::xlog::DestroyXlogInstance((uintptr_t)_instance_ptr);
}

JNIEXPORT jboolean JNICALL Java_com_tencent_mars_xlog_Xlog_hasXlogInstance(
    JNIEnv* env, jobject, jstring _nameprefix) {
    ScopedJstring nameprefix_jstr(env, _nameprefix);
    return mars::xlog::HasXlogInstance(nameprefix_jstr.GetChar()) ? JNI_TRUE : JNI_FALSE;
}
```

### Deprecated JNI functions

The following functions call the deprecated compatibility wrappers:

```cpp
// These wrap to NewXloggerInstance("default", ...)
JNIEXPORT void JNICALL Java_com_tencent_mars_xlog_Xlog_appenderOpen(...) {
    // deprecated: calls appender_open() wrapper
}

JNIEXPORT void JNICALL Java_com_tencent_mars_xlog_Xlog_appenderClose(...) {
    // deprecated: calls appender_close() wrapper
}
```

### Java layer changes (Xlog.java)

- Add `destroyXlogInstance(long instance)` native method
- Add `hasXlogInstance(String nameprefix)` native method
- Mark `appenderOpen()`, `appenderClose()`, `appenderFlush()`, `appenderFlushSync()` as `@Deprecated`

### Java layer changes (Log.java)

- `Log.openLogInstance()` continues to work unchanged (calls `newXlogInstance`)
- `Log.closeLogInstance()` continues to work unchanged (calls `releaseXlogInstance`)
- No changes needed in `LogInstance` inner class

## iOS Objective-C Changes

### New files

| File | Description |
|------|-------------|
| `mars/xlog/objc/MarsXlog.h` | Objective-C public API |
| `mars/xlog/objc/MarsXlog.mm` | Objective-C implementation wrapping C++ API |

### MarsXlog.h

```objc
#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, MarsXLogLevel) {
    MarsXLogLevelVerbose = 0,
    MarsXLogLevelDebug,
    MarsXLogLevelInfo,
    MarsXLogLevelWarn,
    MarsXLogLevelError,
    MarsXLogLevelFatal,
    MarsXLogLevelNone
};

typedef NS_ENUM(NSInteger, MarsXLogAppenderMode) {
    MarsXLogAppenderModeSync = 1,
    MarsXLogAppenderModeAsync = 2
};

typedef NS_ENUM(NSInteger, MarsXLogCompressMode) {
    MarsXLogCompressModeZlib = 1,
    MarsXLogCompressModeZstd = 2
};

@interface MarsXLogConfig : NSObject
@property (nonatomic, assign) MarsXLogLevel level;
@property (nonatomic, assign) MarsXLogAppenderMode mode;
@property (nonatomic, copy) NSString *logdir;
@property (nonatomic, copy) NSString *nameprefix;
@property (nonatomic, copy) NSString *pubkey;
@property (nonatomic, assign) MarsXLogCompressMode compressmode;
@property (nonatomic, assign) NSInteger compresslevel;
@property (nonatomic, copy) NSString *cachedir;
@property (nonatomic, assign) NSInteger cachedays;
@end

@interface MarsXlog : NSObject

+ (uint64_t)newXloggerInstanceWithConfig:(MarsXLogConfig *)config;
+ (uint64_t)getXloggerInstanceWithNameprefix:(NSString *)nameprefix;
+ (void)releaseXloggerInstanceWithNameprefix:(NSString *)nameprefix;
+ (void)destroyXlogInstance:(uint64_t)instance;
+ (BOOL)hasXlogInstance:(NSString *)nameprefix;

+ (void)logWrite:(uint64_t)instance level:(MarsXLogLevel)level
             tag:(NSString *)tag log:(NSString *)log;

+ (MarsXLogLevel)getLogLevel:(uint64_t)instance;
+ (void)setLogLevel:(uint64_t)instance level:(MarsXLogLevel)level;
+ (void)setAppenderMode:(uint64_t)instance mode:(MarsXLogAppenderMode)mode;
+ (void)setConsoleLogOpen:(uint64_t)instance isOpen:(BOOL)isOpen;
+ (void)setMaxFileSize:(uint64_t)instance maxFileSize:(long)maxFileSize;
+ (void)setMaxAliveTime:(uint64_t)instance aliveSeconds:(long)aliveSeconds;

+ (void)flush:(uint64_t)instance isSync:(BOOL)isSync;
+ (void)flushAll:(BOOL)isSync;

@end
```

### MarsXlog.mm

Thin wrapper: each method converts OC types to C++ types, calls the corresponding `mars::xlog::*` function from `xlogger_interface.h`, and converts results back.

### CMakeLists.txt

Add `MarsXlog.mm` to the APPLE source list (line ~47-50 in `mars/xlog/CMakeLists.txt`).

### Export headers

Add `MarsXlog.h` to `mars/xlog/export_include/` and update `mars_utils.py` XLOG_COPY_HEADER_FILES.

## File Modification Summary

| File | Action | Estimated Lines Changed |
|------|--------|------------------------|
| `mars/xlog/xlogger_interface.h` | Modify: add new APIs, change return type | ~+30 |
| `mars/xlog/src/xlogger_interface.cc` | Modify: add new functions, change 0-ptr handling | ~+80, -30 |
| `mars/xlog/appender.h` | Modify: remove global API declarations, add deprecated wrappers | ~+40, -30 |
| `mars/xlog/src/appender.cc` | Modify: remove global state and global API implementations | ~-250 |
| `mars/xlog/jni/Java2C_Xlog.cc` | Modify: add new JNI functions, deprecate old ones | ~+40 |
| `mars/libraries/.../Xlog.java` | Modify: add new native methods, deprecate old ones | ~+15 |
| `mars/libraries/.../Log.java` | No changes needed | 0 |
| `mars/xlog/objc/MarsXlog.h` | **New file** | ~+80 |
| `mars/xlog/objc/MarsXlog.mm` | **New file** | ~+150 |
| `mars/xlog/CMakeLists.txt` | Modify: add MarsXlog.mm | ~+2 |
| `mars/xlog/export_include/xlogger/MarsXlog.h` | **New file** (copy/symlink) | ~+1 |

## Error Handling

- `NewXloggerInstance()` returns 0 if config is invalid (empty logdir or nameprefix).
- `NewXloggerInstance()` returns existing instance if nameprefix already exists (idempotent).
- `DestroyXlogInstance(0)` is a no-op.
- `ReleaseXloggerInstance(nullptr)` is a no-op.
- `XloggerWrite(0, ...)` looks up "default" instance; if not found, drops the log silently.
- All Set*/Get* functions with invalid instance_ptr are no-ops or return defaults.

## Thread Safety

- Global instance map protected by `GetGlobalMutex()`.
- Each `XloggerAppender` has its own `mutex_buffer_async_` and `mutex_log_file_`.
- `DelayRelease` (5-second delay) prevents use-after-free from async threads.
- No changes to the existing thread safety model.

## Testing Strategy

- Unit test: create multiple instances with different configs, verify independent file output.
- Unit test: create instance, destroy by handle, verify cleanup.
- Unit test: deprecated wrappers produce correct behavior.
- Integration test: Android app creates 3 instances (main, network, database), verifies 3 separate log file sets.
- Integration test: iOS app creates 2 instances, verifies independent flush.
- Stress test: concurrent writes to multiple instances from multiple threads.

## Migration Guide

### C++

Before:
```cpp
mars::xlog::appender_open(config);
xlogger_Write(&info, "message");
mars::xlog::appender_close();
```

After:
```cpp
uintptr_t inst = mars::xlog::NewXloggerInstance(config, kLevelInfo);
mars::xlog::XloggerWrite(inst, &info, "message");
mars::xlog::DestroyXlogInstance(inst);
```

### Android (Java)

Before:
```java
Xlog.appenderOpen(config);
// ... logging via global API
Xlog.appenderClose();
```

After:
```java
long inst = xlog.newXlogInstance(config);
xlog.logWrite(inst, level, tag, filename, funcname, line, pid, tid, maintid, log);
xlog.destroyXlogInstance(inst);
```

### iOS (Objective-C)

Before: No OC wrapper existed; direct C++ calls required.

After:
```objc
MarsXLogConfig *config = [[MarsXLogConfig alloc] init];
config.logdir = @"/var/logs";
config.nameprefix = @"main";
config.mode = MarsXLogAppenderModeAsync;

uint64_t inst = [MarsXlog newXloggerInstanceWithConfig:config];
[MarsXlog logWrite:inst level:MarsXLogLevelInfo tag:@"TAG" log:@"message"];
[MarsXlog destroyXlogInstance:inst];
```
