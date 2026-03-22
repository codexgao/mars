# Xlog Multi-Instance Refactor Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor xlog from global singleton + optional multi-instance to a pure multi-instance model where all log operations go through `NewXloggerInstance()`.

**Architecture:** Remove global state (`sg_default_appender`, `sg_release_guard`, etc.) from `appender.cc`. Unify all instance management in `xlogger_interface.cc`. Provide deprecated inline wrappers in `appender.h` for backward compatibility. Add new iOS Objective-C wrapper (`MarsXlog`).

**Tech Stack:** C++11, Android JNI, Objective-C++, CMake

**Spec:** `docs/superpowers/specs/2026-03-22-xlog-multi-instance-refactor-design.md`

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `mars/xlog/src/xlogger_interface.cc` | Modify | Core: all instance CRUD, ResolveInstance, exit cleanup, global callback |
| `mars/xlog/xlogger_interface.h` | Modify | Public C++ API declarations |
| `mars/xlog/src/appender.cc` | Modify | Remove global state and global API implementations |
| `mars/xlog/appender.h` | Modify | Remove old declarations, add deprecated inline wrappers |
| `mars/xlog/jni/Java2C_Xlog.cc` | Modify | Add new JNI functions, update return types |
| `mars/libraries/mars_xlog_sdk/src/main/java/com/tencent/mars/xlog/Xlog.java` | Modify | Add new native methods, deprecate old ones |
| `mars/libraries/mars_xlog_sdk/src/main/java/com/tencent/mars/xlog/Log.java` | Modify | Add `destroyXlogInstance`/`hasXlogInstance` to `LogImp` interface |
| `mars/xlog/objc/MarsXlog.h` | Create | iOS Objective-C public API |
| `mars/xlog/objc/MarsXlog.mm` | Create | iOS Objective-C implementation |
| `mars/xlog/CMakeLists.txt` | Modify | Add MarsXlog.mm to APPLE sources |

---

## Chunk 1: C++ Core Refactor

### Task 1: Modify xlogger_interface.h — new API declarations

**Files:**
- Modify: `mars/xlog/xlogger_interface.h`

- [ ] **Step 1: Update header with new API signatures**

Replace the entire content of `mars/xlog/xlogger_interface.h` with:

```cpp
// Tencent is pleased to support the open source community by making Mars available.
// Copyright (C) 2016 THL A29 Limited, a Tencent company. All rights reserved.

// Licensed under the MIT License (the "License"); you may not use this file except in
// compliance with the License. You may obtain a copy of the License at
// http://opensource.org/licenses/MIT

// Unless required by applicable law or agreed to in writing, software distributed under the License is
// distributed on an "AS IS" basis, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
// either express or implied. See the License for the specific language governing permissions and
// limitations under the License.

#ifndef MARS_LOG_XLOGGER_INTERFACE_H_
#define MARS_LOG_XLOGGER_INTERFACE_H_

#include <stdint.h>

#include <string>
#include <vector>

#include "appender.h"
#include "xloggerbase.h"

namespace mars {
namespace xlog {

// ===== Instance lifecycle =====

// Create a new xlog instance with full independent config.
// Returns uintptr_t (cast from XloggerCategory*), 0 on failure.
// If nameprefix already exists, returns existing instance (idempotent).
uintptr_t NewXloggerInstance(const XLogConfig& _config, TLogLevel _level = kLevelInfo);

// Get existing instance by nameprefix. Returns 0 if not found.
uintptr_t GetXloggerInstance(const char* _nameprefix);

// Destroy instance by nameprefix. No-op if not found.
void ReleaseXloggerInstance(const char* _nameprefix);

// Destroy instance by handle. No-op if 0 or not found.
void DestroyXlogInstance(uintptr_t _instance);

// Check if instance exists.
bool HasXlogInstance(const char* _nameprefix);

// Get all active instance nameprefixes.
std::vector<std::string> GetAllXlogInstanceNames();

// ===== Write =====
void XloggerWrite(uintptr_t _instance_ptr, const XLoggerInfo* _info, const char* _log);

// ===== Query =====
bool IsEnabledFor(uintptr_t _instance_ptr, TLogLevel _level);
TLogLevel GetLevel(uintptr_t _instance_ptr);

// ===== Config =====
void SetLevel(uintptr_t _instance_ptr, TLogLevel _level);
void SetAppenderMode(uintptr_t _instance_ptr, TAppenderMode _mode);
void SetConsoleLogOpen(uintptr_t _instance_ptr, bool _is_open);
void SetMaxFileSize(uintptr_t _instance_ptr, long _max_file_size);
void SetMaxAliveTime(uintptr_t _instance_ptr, long _alive_seconds);

// ===== Flush =====
void Flush(uintptr_t _instance_ptr, bool _is_sync = false);
void FlushAll(bool _is_sync = false);

// ===== Utility (instance-based) =====
bool GetFilePathFromTimespan(uintptr_t _instance_ptr, int _timespan, const char* _prefix, std::vector<std::string>& _filepath_vec);
bool MakeLogFileName(uintptr_t _instance_ptr, int _timespan, const char* _prefix, std::vector<std::string>& _filepath_vec);
bool GetCurrentLogPath(uintptr_t _instance_ptr, char* _log_path, unsigned int _len);
bool GetCurrentLogCachePath(uintptr_t _instance_ptr, char* _log_path, unsigned int _len);

}  // namespace xlog
}  // namespace mars

#endif  // MARS_LOG_XLOGGER_INTERFACE_H_
```

Key changes from original:
- `NewXloggerInstance` returns `uintptr_t` (was `XloggerCategory*`), gains default `_level = kLevelInfo`
- `GetXloggerInstance` returns `uintptr_t` (was `XloggerCategory*`)
- Added: `DestroyXlogInstance`, `HasXlogInstance`, `GetAllXlogInstanceNames`
- Added: `GetFilePathFromTimespan`, `MakeLogFileName`, `GetCurrentLogPath`, `GetCurrentLogCachePath`
- Added: `#include <string>` and `#include <vector>` for new return types
- Removed: forward declaration of `mars::comm::XloggerCategory` (no longer exposed)

- [ ] **Step 2: Commit**

```bash
git add mars/xlog/xlogger_interface.h
git commit -m "refactor(xlog): update xlogger_interface.h with pure multi-instance API"
```

---

### Task 2: Rewrite xlogger_interface.cc — unified instance management

**Files:**
- Modify: `mars/xlog/src/xlogger_interface.cc`

- [ ] **Step 1: Rewrite xlogger_interface.cc**

Replace the entire content of `mars/xlog/src/xlogger_interface.cc` with:

```cpp
// Tencent is pleased to support the open source community by making Mars available.
// Copyright (C) 2016 THL A29 Limited, a Tencent company. All rights reserved.

// Licensed under the MIT License (the "License"); you may not use this file except in
// compliance with the License. You may obtain a copy of the License at
// http://opensource.org/licenses/MIT

// Unless required by applicable law or agreed to in writing, software distributed under the License is
// distributed on an "AS IS" basis, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
// either express or implied. See the License for the specific language governing permissions and
// limitations under the License.

#include "mars/xlog/xlogger_interface.h"

#include <functional>
#include <map>
#include <string>
#include <vector>

#include "mars/comm/thread/lock.h"
#include "mars/comm/thread/mutex.h"
#include "mars/comm/xlogger/xlogger.h"
#include "mars/comm/xlogger/xlogger_category.h"
#include "mars/comm/bootrun.h"
#include "xlogger_appender.h"

using namespace mars::comm;
namespace mars {
namespace xlog {

static Mutex& GetGlobalMutex() {
    static Mutex sg_mutex;
    return sg_mutex;
}

static std::map<std::string, XloggerCategory*>& GetGlobalInstanceMap() {
    static std::map<std::string, XloggerCategory*> sg_map;
    return sg_map;
}

// Reverse lookup: find nameprefix for a given XloggerCategory pointer.
static std::string FindNameprefixByInstance(uintptr_t _instance) {
    auto& xmap = GetGlobalInstanceMap();
    for (auto it = xmap.begin(); it != xmap.end(); ++it) {
        if (reinterpret_cast<uintptr_t>(it->second) == _instance) {
            return it->first;
        }
    }
    return "";
}

// Resolve instance_ptr == 0 to "default" instance.
static uintptr_t ResolveInstance(uintptr_t _instance_ptr) {
    if (0 != _instance_ptr) return _instance_ptr;
    auto it = GetGlobalInstanceMap().find("default");
    if (it != GetGlobalInstanceMap().end()) {
        return reinterpret_cast<uintptr_t>(it->second);
    }
    return 0;
}

// Helper: get appender from instance pointer (caller must ensure _instance_ptr != 0).
static XloggerAppender* GetAppenderFromInstance(uintptr_t _instance_ptr) {
    XloggerCategory* category = reinterpret_cast<XloggerCategory*>(_instance_ptr);
    return reinterpret_cast<XloggerAppender*>(category->GetAppender());
}

// Global callback for xlogger_Write() / xlogger2() macros.
// Forwards to the "default" instance's appender.
static void DefaultInstanceAppenderCallback(const XLoggerInfo* _info, const char* _log) {
    uintptr_t inst = ResolveInstance(0);
    if (0 == inst) return;
    XloggerCategory* category = reinterpret_cast<XloggerCategory*>(inst);
    category->Write(_info, _log);
}

// Process exit cleanup: flush and close all instances.
static void ReleaseAllInstances() {
    ScopedLock lock(GetGlobalMutex());
    auto& xmap = GetGlobalInstanceMap();
    for (auto it = xmap.begin(); it != xmap.end(); ++it) {
        XloggerCategory* category = it->second;
        XloggerAppender* appender = reinterpret_cast<XloggerAppender*>(category->GetAppender());
        appender->Close();
        // Do NOT DelayRelease here — process is exiting, avoid dangling threads.
    }
    xmap.clear();
}

static bool sg_exit_registered = false;

// ===== Instance lifecycle =====

uintptr_t NewXloggerInstance(const XLogConfig& _config, TLogLevel _level) {
    if (_config.logdir_.empty() || _config.nameprefix_.empty()) {
        return 0;
    }

    ScopedLock lock(GetGlobalMutex());

    // Register exit handler once.
    if (!sg_exit_registered) {
        sg_exit_registered = true;
        BOOT_RUN_EXIT(ReleaseAllInstances);
    }

    auto it = GetGlobalInstanceMap().find(_config.nameprefix_);
    if (it != GetGlobalInstanceMap().end()) {
        return reinterpret_cast<uintptr_t>(it->second);
    }

    XloggerAppender* appender = XloggerAppender::NewInstance(_config, 0);

    using namespace std::placeholders;
    XloggerCategory* category = XloggerCategory::NewInstance(
        reinterpret_cast<uintptr_t>(appender),
        std::bind(&XloggerAppender::Write, appender, _1, _2));
    category->SetLevel(_level);
    GetGlobalInstanceMap()[_config.nameprefix_] = category;

    // If this is the "default" instance, register the global xlogger callback
    // so that xlogger2() / xlogger_Write() macros continue to work.
    if (_config.nameprefix_ == "default") {
        xlogger_SetAppender(&DefaultInstanceAppenderCallback);
    }

    return reinterpret_cast<uintptr_t>(category);
}

uintptr_t GetXloggerInstance(const char* _nameprefix) {
    if (nullptr == _nameprefix) {
        return 0;
    }

    ScopedLock lock(GetGlobalMutex());
    auto it = GetGlobalInstanceMap().find(_nameprefix);
    if (it != GetGlobalInstanceMap().end()) {
        return reinterpret_cast<uintptr_t>(it->second);
    }

    return 0;
}

void ReleaseXloggerInstance(const char* _nameprefix) {
    if (nullptr == _nameprefix) {
        return;
    }

    ScopedLock lock(GetGlobalMutex());
    auto it = GetGlobalInstanceMap().find(_nameprefix);
    if (it == GetGlobalInstanceMap().end()) {
        return;
    }

    // If releasing "default", unregister global callback.
    if (std::string(_nameprefix) == "default") {
        xlogger_SetAppender(nullptr);
    }

    XloggerCategory* category = it->second;
    XloggerAppender* appender = reinterpret_cast<XloggerAppender*>(category->GetAppender());
    appender->Close();
    XloggerAppender::DelayRelease(appender);
    XloggerCategory::DelayRelease(category);
    GetGlobalInstanceMap().erase(it);
}

void DestroyXlogInstance(uintptr_t _instance) {
    if (0 == _instance) return;
    ScopedLock lock(GetGlobalMutex());

    std::string nameprefix = FindNameprefixByInstance(_instance);
    if (nameprefix.empty()) return;

    auto it = GetGlobalInstanceMap().find(nameprefix);
    if (it == GetGlobalInstanceMap().end()) return;

    // If destroying "default", unregister global callback.
    if (nameprefix == "default") {
        xlogger_SetAppender(nullptr);
    }

    XloggerCategory* category = it->second;
    XloggerAppender* appender = reinterpret_cast<XloggerAppender*>(category->GetAppender());
    appender->Close();
    XloggerAppender::DelayRelease(appender);
    XloggerCategory::DelayRelease(category);
    GetGlobalInstanceMap().erase(it);
}

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

// ===== Write =====

void XloggerWrite(uintptr_t _instance_ptr, const XLoggerInfo* _info, const char* _log) {
    uintptr_t resolved = ResolveInstance(_instance_ptr);
    if (0 == resolved) return;
    XloggerCategory* category = reinterpret_cast<XloggerCategory*>(resolved);
    category->Write(_info, _log);
}

// ===== Query =====

bool IsEnabledFor(uintptr_t _instance_ptr, TLogLevel _level) {
    uintptr_t resolved = ResolveInstance(_instance_ptr);
    if (0 == resolved) {
        return xlogger_IsEnabledFor(_level);
    }
    XloggerCategory* category = reinterpret_cast<XloggerCategory*>(resolved);
    return category->IsEnabledFor(_level);
}

TLogLevel GetLevel(uintptr_t _instance_ptr) {
    uintptr_t resolved = ResolveInstance(_instance_ptr);
    if (0 == resolved) {
        return xlogger_Level();
    }
    XloggerCategory* category = reinterpret_cast<XloggerCategory*>(resolved);
    return category->GetLevel();
}

// ===== Config =====

void SetLevel(uintptr_t _instance_ptr, TLogLevel _level) {
    uintptr_t resolved = ResolveInstance(_instance_ptr);
    if (0 == resolved) return;
    XloggerCategory* category = reinterpret_cast<XloggerCategory*>(resolved);
    category->SetLevel(_level);
}

void SetAppenderMode(uintptr_t _instance_ptr, TAppenderMode _mode) {
    uintptr_t resolved = ResolveInstance(_instance_ptr);
    if (0 == resolved) return;
    XloggerAppender* appender = GetAppenderFromInstance(resolved);
    appender->SetMode(_mode);
}

void Flush(uintptr_t _instance_ptr, bool _is_sync) {
    uintptr_t resolved = ResolveInstance(_instance_ptr);
    if (0 == resolved) return;
    XloggerAppender* appender = GetAppenderFromInstance(resolved);
    _is_sync ? appender->FlushSync() : appender->Flush();
}

void FlushAll(bool _is_sync) {
    // Copy appender list under lock, then flush without holding global lock
    // to avoid blocking NewXloggerInstance/DestroyXlogInstance during I/O.
    std::vector<XloggerAppender*> appenders;
    {
        ScopedLock lock(GetGlobalMutex());
        auto& xmap = GetGlobalInstanceMap();
        for (auto it = xmap.begin(); it != xmap.end(); ++it) {
            XloggerCategory* category = it->second;
            appenders.push_back(
                reinterpret_cast<XloggerAppender*>(category->GetAppender()));
        }
    }
    for (auto* appender : appenders) {
        _is_sync ? appender->FlushSync() : appender->Flush();
    }
}

void SetConsoleLogOpen(uintptr_t _instance_ptr, bool _is_open) {
    uintptr_t resolved = ResolveInstance(_instance_ptr);
    if (0 == resolved) return;
    XloggerAppender* appender = GetAppenderFromInstance(resolved);
    appender->SetConsoleLog(_is_open);
}

void SetMaxFileSize(uintptr_t _instance_ptr, long _max_file_size) {
    uintptr_t resolved = ResolveInstance(_instance_ptr);
    if (0 == resolved) return;
    XloggerAppender* appender = GetAppenderFromInstance(resolved);
    appender->SetMaxFileSize(_max_file_size);
}

void SetMaxAliveTime(uintptr_t _instance_ptr, long _alive_seconds) {
    uintptr_t resolved = ResolveInstance(_instance_ptr);
    if (0 == resolved) return;
    XloggerAppender* appender = GetAppenderFromInstance(resolved);
    appender->SetMaxAliveDuration(_alive_seconds);
}

// ===== Utility (instance-based) =====

bool GetFilePathFromTimespan(uintptr_t _instance_ptr, int _timespan, const char* _prefix, std::vector<std::string>& _filepath_vec) {
    uintptr_t resolved = ResolveInstance(_instance_ptr);
    if (0 == resolved) return false;
    XloggerAppender* appender = GetAppenderFromInstance(resolved);
    return appender->GetfilepathFromTimespan(_timespan, _prefix, _filepath_vec);
}

bool MakeLogFileName(uintptr_t _instance_ptr, int _timespan, const char* _prefix, std::vector<std::string>& _filepath_vec) {
    uintptr_t resolved = ResolveInstance(_instance_ptr);
    if (0 == resolved) return false;
    XloggerAppender* appender = GetAppenderFromInstance(resolved);
    return appender->MakeLogfileName(_timespan, _prefix, _filepath_vec);
}

bool GetCurrentLogPath(uintptr_t _instance_ptr, char* _log_path, unsigned int _len) {
    uintptr_t resolved = ResolveInstance(_instance_ptr);
    if (0 == resolved) return false;
    XloggerAppender* appender = GetAppenderFromInstance(resolved);
    return appender->GetCurrentLogPath(_log_path, _len);
}

bool GetCurrentLogCachePath(uintptr_t _instance_ptr, char* _log_path, unsigned int _len) {
    uintptr_t resolved = ResolveInstance(_instance_ptr);
    if (0 == resolved) return false;
    XloggerAppender* appender = GetAppenderFromInstance(resolved);
    return appender->GetCurrentLogCachePath(_log_path, _len);
}

}  // namespace xlog
}  // namespace mars
```

Key changes from original:
- All `_instance_ptr == 0` branches now use `ResolveInstance()` (looks up "default")
- No more fallthrough to global `xlogger_*` / `appender_*` functions
- Added: `DestroyXlogInstance`, `HasXlogInstance`, `GetAllXlogInstanceNames`
- Added: `DefaultInstanceAppenderCallback` for global xlogger macro support
- Added: `ReleaseAllInstances` + `BOOT_RUN_EXIT` for process exit cleanup
- Added: `GetFilePathFromTimespan`, `MakeLogFileName`, `GetCurrentLogPath`, `GetCurrentLogCachePath`
- `ReleaseXloggerInstance` now calls `appender->Close()` before `DelayRelease`
- `NewXloggerInstance` returns `uintptr_t` instead of `XloggerCategory*`

- [ ] **Step 2: Verify header includes exist**

Check that `mars/comm/bootrun.h` exists and provides the `BOOT_RUN_EXIT` macro:

```bash
grep -r "BOOT_RUN_EXIT" mars/comm/ --include="*.h" -l
```

Expected: find at least one header file defining the macro.

- [ ] **Step 3: Commit**

```bash
git add mars/xlog/src/xlogger_interface.cc
git commit -m "refactor(xlog): rewrite xlogger_interface.cc with unified multi-instance model"
```

---

### Task 3: Clean up appender.cc — remove global state

**Files:**
- Modify: `mars/xlog/src/appender.cc`

- [ ] **Step 1: Remove global state and global API implementations**

Remove lines ~1262-1454 from `appender.cc`. Specifically, remove everything from the `////////////////////////////////////////////////////////////////////////////////////` comment through the end of the file. This includes:

- `sg_default_appender`, `sg_release_guard`, `sg_default_console_log_open`, `sg_mutex`, `sg_max_byte_size`, `sg_max_alive_time` globals
- `xlogger_appender()` callback
- `appender_release_default_appender()`
- `appender_open()`, `appender_close()`, `appender_flush()`, `appender_flush_sync()`
- `appender_setmode()`, `appender_get_current_log_path()`, `appender_get_current_log_cache_path()`
- `appender_set_console_log()`, `appender_set_max_file_size()`, `appender_set_max_alive_duration()`
- `appender_getfilepath_from_timespan()`, `appender_make_logfile_name()`
- `appender_oneshot_flush()`
- `xlogger_dump()`, `xlogger_memory_dump()` (move `xlogger_memory_dump` to keep — see below)

**Keep `xlogger_memory_dump()`**: This function does not depend on `sg_default_appender`. It is a standalone utility. Move it before the removed block, or leave it after the namespace close, but ensure it still compiles.

**Keep `appender_oneshot_flush()`**: This function creates its own scoped appender instance (does not use `sg_default_appender`). However, it references `sg_max_byte_size` which is being removed. Change it to use `0` instead:

Replace the removed block with only these two surviving functions:

```cpp
////////////////////////////////////////////////////////////////////////////////////

void appender_oneshot_flush(const XLogConfig& _config, TFileIOAction* _result) {
    auto* scoped_appender = XloggerAppender::NewInstance(_config, 0, true);
    scoped_appender->TreatMappingAsFileAndFlush(_result);
    scoped_appender->Close();
    XloggerAppender::DelayRelease(scoped_appender);
}

}  // namespace xlog
}  // namespace mars

const char* xlogger_memory_dump(const void* _dumpbuffer, size_t _len) {
    if (NULL == _dumpbuffer || 0 == _len) {
        return "";
    }

    SCOPE_ERRNO();

    thread_local std::string buffer;
    if (!buffer.empty()) {
        buffer.clear();
    }

    const char* src_buffer = reinterpret_cast<const char*>(_dumpbuffer);
    buffer += "\n";
    buffer += std::to_string(_len) + " bytes:\n";

    int calc_dst_buffer_len = calc_dump_required_length(32) + 1;
    char* dst_buffer = new char[calc_dst_buffer_len];

    for (int src_offset = 0; src_offset < (int)_len && buffer.size() < kMaxDumpLength;) {
        int dst_leftbytes = kMaxDumpLength - buffer.size();
        int bytes = std::min((int)_len - src_offset, 32);

        while (bytes > 0 && calc_dump_required_length(bytes) >= dst_leftbytes) {
            --bytes;
        }
        if (bytes <= 0) {
            break;
        }

        memset(dst_buffer, 0, calc_dst_buffer_len);
        to_string(src_buffer + src_offset, bytes, dst_buffer);
        buffer += dst_buffer;

        src_offset += bytes;

        // next line
        buffer += "\n";
    }

    delete[] dst_buffer;
    return buffer.c_str();
}
```

Note: `xlogger_dump()` depends on `sg_default_appender->Dump()`. Since `Dump()` is a method on `XloggerAppender`, callers who need it can get the appender via the instance-based API. Remove `xlogger_dump()` entirely — it was only usable through the global instance anyway.

- [ ] **Step 2: Commit**

```bash
git add mars/xlog/src/appender.cc
git commit -m "refactor(xlog): remove global state and global API implementations from appender.cc"
```

---

### Task 4: Update appender.h — deprecated inline wrappers

**Files:**
- Modify: `mars/xlog/appender.h`

- [ ] **Step 1: Replace appender.h content**

Replace the entire content of `mars/xlog/appender.h` with:

```cpp
// Tencent is pleased to support the open source community by making Mars available.
// Copyright (C) 2016 THL A29 Limited, a Tencent company. All rights reserved.

// Licensed under the MIT License (the "License"); you may not use this file except in
// compliance with the License. You may obtain a copy of the License at
// http://opensource.org/licenses/MIT

// Unless required by applicable law or agreed to in writing, software distributed under the License is
// distributed on an "AS IS" basis, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
// either express or implied. See the License for the specific language governing permissions and
// limitations under the License.

/*
 * appender.h
 *
 *  Created on: 2013-3-7
 *      Author: yerungui
 */

#ifndef APPENDER_H_
#define APPENDER_H_

#include <stdint.h>

#include <string>
#include <vector>

namespace mars {
namespace xlog {

enum TAppenderMode {
    kAppenderAsync,
    kAppenderSync,
};

enum TCompressMode {
    kZlib,
    kZstd,
};

enum TFileIOAction {
    kActionNone = 0,
    kActionSuccess = 1,
    kActionUnnecessary = 2,
    kActionOpenFailed = 3,
    kActionReadFailed = 4,
    kActionWriteFailed = 5,
    kActionCloseFailed = 6,
    kActionRemoveFailed = 7,
};

struct XLogConfig {
    TAppenderMode mode_ = kAppenderAsync;
    std::string logdir_;
    std::string nameprefix_;
    std::string pub_key_;
    TCompressMode compress_mode_ = kZlib;
    int compress_level_ = 6;
    std::string cachedir_;
    int cache_days_ = 0;
};

#ifdef __APPLE__
enum TConsoleFun {
    kConsolePrintf,
    kConsoleNSLog,
    kConsoleOSLog,
};

void appender_set_console_fun(TConsoleFun _fun);
#endif

// Standalone utility — does not require a global instance.
void appender_oneshot_flush(const XLogConfig& _config, TFileIOAction* _result);

}  // namespace xlog
}  // namespace mars

// ===== Deprecated backward-compatible wrappers =====
// These create/operate on a "default" named instance internally.
// New code should use NewXloggerInstance() from xlogger_interface.h instead.

#include "xlogger_interface.h"

namespace mars {
namespace xlog {

#if defined(__GNUC__) || defined(__clang__)
#define XLOG_DEPRECATED __attribute__((deprecated("Use NewXloggerInstance/ReleaseXloggerInstance instead")))
#elif defined(_MSC_VER)
#define XLOG_DEPRECATED __declspec(deprecated("Use NewXloggerInstance/ReleaseXloggerInstance instead"))
#else
#define XLOG_DEPRECATED
#endif

XLOG_DEPRECATED
inline void appender_open(const XLogConfig& _config) {
    XLogConfig default_config = _config;
    default_config.nameprefix_ = "default";
    NewXloggerInstance(default_config, kLevelInfo);
}

XLOG_DEPRECATED
inline void appender_close() {
    ReleaseXloggerInstance("default");
}

XLOG_DEPRECATED
inline void appender_flush() {
    FlushAll(false);
}

XLOG_DEPRECATED
inline void appender_flush_sync() {
    FlushAll(true);
}

XLOG_DEPRECATED
inline void appender_setmode(TAppenderMode _mode) {
    uintptr_t inst = GetXloggerInstance("default");
    if (inst) SetAppenderMode(inst, _mode);
}

XLOG_DEPRECATED
inline void appender_set_console_log(bool _is_open) {
    uintptr_t inst = GetXloggerInstance("default");
    if (inst) SetConsoleLogOpen(inst, _is_open);
}

XLOG_DEPRECATED
inline void appender_set_max_file_size(uint64_t _max_byte_size) {
    uintptr_t inst = GetXloggerInstance("default");
    if (inst) SetMaxFileSize(inst, _max_byte_size);
}

XLOG_DEPRECATED
inline void appender_set_max_alive_duration(long _max_time) {
    uintptr_t inst = GetXloggerInstance("default");
    if (inst) SetMaxAliveTime(inst, _max_time);
}

XLOG_DEPRECATED
inline bool appender_getfilepath_from_timespan(int _timespan, const char* _prefix, std::vector<std::string>& _filepath_vec) {
    uintptr_t inst = GetXloggerInstance("default");
    if (!inst) return false;
    return GetFilePathFromTimespan(inst, _timespan, _prefix, _filepath_vec);
}

XLOG_DEPRECATED
inline bool appender_make_logfile_name(int _timespan, const char* _prefix, std::vector<std::string>& _filepath_vec) {
    uintptr_t inst = GetXloggerInstance("default");
    if (!inst) return false;
    return MakeLogFileName(inst, _timespan, _prefix, _filepath_vec);
}

XLOG_DEPRECATED
inline bool appender_get_current_log_path(char* _log_path, unsigned int _len) {
    uintptr_t inst = GetXloggerInstance("default");
    if (!inst) return false;
    return GetCurrentLogPath(inst, _log_path, _len);
}

XLOG_DEPRECATED
inline bool appender_get_current_log_cache_path(char* _log_path, unsigned int _len) {
    uintptr_t inst = GetXloggerInstance("default");
    if (!inst) return false;
    return GetCurrentLogCachePath(inst, _log_path, _len);
}

#undef XLOG_DEPRECATED

}  // namespace xlog
}  // namespace mars

#endif /* APPENDER_H_ */
```

Key changes:
- Removed all non-inline function declarations that were moved to `xlogger_interface.h`
- Kept: enums, `XLogConfig`, `TConsoleFun`, `appender_set_console_fun`, `appender_oneshot_flush`
- Added: `#include "xlogger_interface.h"` for deprecated wrappers
- Added: all deprecated inline wrappers with `XLOG_DEPRECATED` attribute
- Deprecated wrappers handle `appender_open` forcing `nameprefix_ = "default"`

- [ ] **Step 2: Commit**

```bash
git add mars/xlog/appender.h
git commit -m "refactor(xlog): replace global API declarations with deprecated inline wrappers in appender.h"
```

---

### Task 5: Verify C++ core compiles

**Files:** None (verification only)

- [ ] **Step 1: Check for circular include issues**

`appender.h` now includes `xlogger_interface.h`, and `xlogger_interface.h` includes `appender.h`. This is a circular dependency. Fix by moving the `#include "xlogger_interface.h"` and the deprecated wrappers into a separate section that is only included when both headers are available, OR restructure:

**Fix**: Move the deprecated wrappers out of `appender.h` into a new inline convenience — OR simply remove the `#include "appender.h"` from `xlogger_interface.h` since it only needs `XLogConfig` and enums.

Check if `xlogger_interface.h` can forward-declare what it needs from `appender.h`:
- It needs `XLogConfig` (struct), `TAppenderMode` (enum), `TLogLevel` (from xloggerbase.h)
- `XLogConfig` is a struct with std::string members — cannot be forward-declared

**Resolution**: Keep `xlogger_interface.h` including `appender.h` (for `XLogConfig`). In `appender.h`, place the `#include "xlogger_interface.h"` and deprecated wrappers **after** the main `#endif`, using a separate include guard:

Actually, simpler approach: Since `xlogger_interface.h` includes `appender.h`, and `appender.h` would include `xlogger_interface.h` — the include guard `#ifndef MARS_LOG_XLOGGER_INTERFACE_H_` prevents the circular issue. When `appender.h` is included first, it will try to include `xlogger_interface.h`, which includes `appender.h` again — but the `#ifndef APPENDER_H_` guard stops it. The deprecated wrappers in `appender.h` reference functions declared in `xlogger_interface.h`, which is already included by that point.

When `xlogger_interface.h` is included first, it includes `appender.h`, which includes `xlogger_interface.h` again — but the guard stops it. However, the deprecated wrappers in `appender.h` reference `NewXloggerInstance` etc., which haven't been declared yet at that point (they are below the `#include "appender.h"` in `xlogger_interface.h`).

**This IS a problem.** Fix: Remove `#include "appender.h"` from `xlogger_interface.h`. Instead, forward-include what's needed. But `XLogConfig` can't be forward-declared.

**Best fix**: Extract `XLogConfig` and enums into a separate header `mars/xlog/xlog_config.h`. Both `appender.h` and `xlogger_interface.h` include it. No circular dependency.

Create `mars/xlog/xlog_config.h`:

```cpp
#ifndef MARS_XLOG_CONFIG_H_
#define MARS_XLOG_CONFIG_H_

#include <string>

namespace mars {
namespace xlog {

enum TAppenderMode {
    kAppenderAsync,
    kAppenderSync,
};

enum TCompressMode {
    kZlib,
    kZstd,
};

enum TFileIOAction {
    kActionNone = 0,
    kActionSuccess = 1,
    kActionUnnecessary = 2,
    kActionOpenFailed = 3,
    kActionReadFailed = 4,
    kActionWriteFailed = 5,
    kActionCloseFailed = 6,
    kActionRemoveFailed = 7,
};

struct XLogConfig {
    TAppenderMode mode_ = kAppenderAsync;
    std::string logdir_;
    std::string nameprefix_;
    std::string pub_key_;
    TCompressMode compress_mode_ = kZlib;
    int compress_level_ = 6;
    std::string cachedir_;
    int cache_days_ = 0;
};

}  // namespace xlog
}  // namespace mars

#endif  // MARS_XLOG_CONFIG_H_
```

Then update `appender.h` to `#include "xlog_config.h"` (remove the enum/struct definitions).
Update `xlogger_interface.h` to `#include "xlog_config.h"` instead of `#include "appender.h"`.

This breaks the circular dependency cleanly:
- `xlog_config.h` — standalone (enums + XLogConfig)
- `xlogger_interface.h` — includes `xlog_config.h` + `xloggerbase.h`
- `appender.h` — includes `xlog_config.h` + `xlogger_interface.h` (for deprecated wrappers)

- [ ] **Step 2: Create xlog_config.h**

Create `mars/xlog/xlog_config.h` with the content above.

- [ ] **Step 3: Update appender.h**

Remove the enum/struct definitions from `appender.h` and replace with `#include "xlog_config.h"`. The `#include "xlogger_interface.h"` for deprecated wrappers stays.

- [ ] **Step 4: Update xlogger_interface.h**

Change `#include "appender.h"` to `#include "xlog_config.h"`.

- [ ] **Step 5: Update any files that include appender.h only for XLogConfig**

Search for `#include "mars/xlog/appender.h"` or `#include "appender.h"` across the codebase. Files that only need `XLogConfig`/enums can switch to `xlog_config.h`. Files that need the deprecated wrappers keep `appender.h`.

```bash
grep -r '#include.*appender\.h' mars/ --include="*.cc" --include="*.h" --include="*.mm" --include="*.cpp" -l
```

- [ ] **Step 6: Commit**

```bash
git add mars/xlog/xlog_config.h mars/xlog/appender.h mars/xlog/xlogger_interface.h
git commit -m "refactor(xlog): extract XLogConfig into xlog_config.h to break circular include"
```

---

## Chunk 2: Android JNI + Java Layer

### Task 6: Update Java2C_Xlog.cc — adapt JNI to new C++ API

**Files:**
- Modify: `mars/xlog/jni/Java2C_Xlog.cc`

- [ ] **Step 1: Update newXlogInstance to use uintptr_t return**

In `Java2C_Xlog.cc`, the `newXlogInstance` function currently does:
```cpp
mars::comm::XloggerCategory* category = mars::xlog::NewXloggerInstance(config, (TLogLevel)level);
if (nullptr == category) {
    return 0;
}
return reinterpret_cast<uintptr_t>(category);
```

Change to (since `NewXloggerInstance` now returns `uintptr_t`):
```cpp
uintptr_t instance = mars::xlog::NewXloggerInstance(config, (TLogLevel)level);
return (jlong)instance;
```

- [ ] **Step 2: Update getXlogInstance similarly**

Change from:
```cpp
mars::comm::XloggerCategory* category = mars::xlog::GetXloggerInstance(nameprefix_jstr.GetChar());
if (nullptr == category) {
    return 0;
}
return reinterpret_cast<uintptr_t>(category);
```

To:
```cpp
uintptr_t instance = mars::xlog::GetXloggerInstance(nameprefix_jstr.GetChar());
return (jlong)instance;
```

- [ ] **Step 3: Add new JNI functions**

Add before the closing `}` of the `extern "C"` block:

```cpp
JNIEXPORT void JNICALL Java_com_tencent_mars_xlog_Xlog_destroyXlogInstance(JNIEnv* env,
                                                                            jobject,
                                                                            jlong _instance_ptr) {
    mars::xlog::DestroyXlogInstance((uintptr_t)_instance_ptr);
}

JNIEXPORT jboolean JNICALL Java_com_tencent_mars_xlog_Xlog_hasXlogInstance(JNIEnv* env,
                                                                            jobject,
                                                                            jstring _nameprefix) {
    if (NULL == _nameprefix) return JNI_FALSE;
    ScopedJstring nameprefix_jstr(env, _nameprefix);
    return mars::xlog::HasXlogInstance(nameprefix_jstr.GetChar()) ? JNI_TRUE : JNI_FALSE;
}
```

- [ ] **Step 4: Remove the `#include "mars/comm/xlogger/xlogger_category.h"` reference**

The JNI file no longer needs to know about `XloggerCategory`. Remove any include of `xlogger_category.h` if present. The file already includes `mars/xlog/xlogger_interface.h` which is sufficient.

- [ ] **Step 5: Commit**

```bash
git add mars/xlog/jni/Java2C_Xlog.cc
git commit -m "refactor(xlog): update JNI layer for multi-instance API changes"
```

---

### Task 7: Update Xlog.java — add new native methods

**Files:**
- Modify: `mars/libraries/mars_xlog_sdk/src/main/java/com/tencent/mars/xlog/Xlog.java`

- [ ] **Step 1: Add new native method declarations**

Add after line 158 (`public native long newXlogInstance(XLogConfig logConfig);`):

```java
	public native void destroyXlogInstance(long logInstancePtr);

	public native boolean hasXlogInstance(String nameprefix);
```

- [ ] **Step 2: Mark deprecated methods with @Deprecated**

Add `@Deprecated` annotation before:
- `private static native void appenderOpen(XLogConfig logConfig);` (line 163)
- `public native void appenderClose();` (line 166)

Also add `@Deprecated` to the `open()` static method (line 53) and the `appenderOpen(int, ...)` override (line 108).

- [ ] **Step 3: Commit**

```bash
git add mars/libraries/mars_xlog_sdk/src/main/java/com/tencent/mars/xlog/Xlog.java
git commit -m "refactor(xlog): add destroyXlogInstance/hasXlogInstance to Xlog.java, deprecate old API"
```

---

### Task 8: Update Log.java LogImp interface

**Files:**
- Modify: `mars/libraries/mars_xlog_sdk/src/main/java/com/tencent/mars/xlog/Log.java`

- [ ] **Step 1: Add new methods to LogImp interface**

In the `LogImp` interface (around line 31-66), add:

```java
        void destroyXlogInstance(long logInstancePtr);

        boolean hasXlogInstance(String nameprefix);
```

- [ ] **Step 2: Update debugLog anonymous class**

The `debugLog` anonymous class implements `LogImp`. Add stub implementations:

```java
        @Override
        public void destroyXlogInstance(long logInstancePtr) {
            // no-op for debug log
        }

        @Override
        public boolean hasXlogInstance(String nameprefix) {
            return false;
        }
```

- [ ] **Step 3: Commit**

```bash
git add mars/libraries/mars_xlog_sdk/src/main/java/com/tencent/mars/xlog/Log.java
git commit -m "refactor(xlog): add destroyXlogInstance/hasXlogInstance to LogImp interface"
```

---

## Chunk 3: iOS Objective-C Wrapper

### Task 9: Create MarsXlog.h

**Files:**
- Create: `mars/xlog/objc/MarsXlog.h`

- [ ] **Step 1: Create MarsXlog.h**

Create `mars/xlog/objc/MarsXlog.h` with the full content from the spec. Key points:
- `MarsXLogAppenderMode`: Async=0, Sync=1 (matches C++ `kAppenderAsync=0, kAppenderSync=1`)
- `MarsXLogCompressMode`: Zlib=0, Zstd=1 (matches C++ `kZlib=0, kZstd=1`)
- All instance methods take `uint64_t` handle
- `MarsXLogConfig` is an NSObject with properties matching `XLogConfig`

```objc
// Tencent is pleased to support the open source community by making Mars available.
// Copyright (C) 2016 THL A29 Limited, a Tencent company. All rights reserved.

// Licensed under the MIT License (the "License"); you may not use this file except in
// compliance with the License. You may obtain a copy of the License at
// http://opensource.org/licenses/MIT

// Unless required by applicable law or agreed to in writing, software distributed under the License is
// distributed on an "AS IS" basis, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
// either express or implied. See the License for the specific language governing permissions and
// limitations under the License.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

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
    MarsXLogAppenderModeAsync = 0,
    MarsXLogAppenderModeSync = 1
};

typedef NS_ENUM(NSInteger, MarsXLogCompressMode) {
    MarsXLogCompressModeZlib = 0,
    MarsXLogCompressModeZstd = 1
};

@interface MarsXLogConfig : NSObject
@property (nonatomic, assign) MarsXLogLevel level;
@property (nonatomic, assign) MarsXLogAppenderMode mode;
@property (nonatomic, copy) NSString *logdir;
@property (nonatomic, copy) NSString *nameprefix;
@property (nonatomic, copy) NSString *pubkey;
@property (nonatomic, assign) MarsXLogCompressMode compressmode;
@property (nonatomic, assign) NSInteger compresslevel;
@property (nonatomic, copy, nullable) NSString *cachedir;
@property (nonatomic, assign) NSInteger cachedays;
@end

@interface MarsXlog : NSObject

// ===== Instance lifecycle =====
+ (uint64_t)newXloggerInstanceWithConfig:(MarsXLogConfig *)config;
+ (uint64_t)getXloggerInstanceWithNameprefix:(NSString *)nameprefix;
+ (void)releaseXloggerInstanceWithNameprefix:(NSString *)nameprefix;
+ (void)destroyXlogInstance:(uint64_t)instance;
+ (BOOL)hasXlogInstance:(NSString *)nameprefix;
+ (NSArray<NSString *> *)getAllXlogInstanceNames;

// ===== Write =====
+ (void)logWrite:(uint64_t)instance
           level:(MarsXLogLevel)level
             tag:(NSString *)tag
             log:(NSString *)log;

// ===== Query =====
+ (MarsXLogLevel)getLogLevel:(uint64_t)instance;

// ===== Config =====
+ (void)setLogLevel:(uint64_t)instance level:(MarsXLogLevel)level;
+ (void)setAppenderMode:(uint64_t)instance mode:(MarsXLogAppenderMode)mode;
+ (void)setConsoleLogOpen:(uint64_t)instance isOpen:(BOOL)isOpen;
+ (void)setMaxFileSize:(uint64_t)instance maxFileSize:(long)maxFileSize;
+ (void)setMaxAliveTime:(uint64_t)instance aliveSeconds:(long)aliveSeconds;

// ===== Flush =====
+ (void)flush:(uint64_t)instance isSync:(BOOL)isSync;
+ (void)flushAll:(BOOL)isSync;

@end

NS_ASSUME_NONNULL_END
```

- [ ] **Step 2: Commit**

```bash
git add mars/xlog/objc/MarsXlog.h
git commit -m "feat(xlog): add MarsXlog.h Objective-C public API for multi-instance xlog"
```

---

### Task 10: Create MarsXlog.mm

**Files:**
- Create: `mars/xlog/objc/MarsXlog.mm`

- [ ] **Step 1: Create MarsXlog.mm**

```objc++
// Tencent is pleased to support the open source community by making Mars available.
// Copyright (C) 2016 THL A29 Limited, a Tencent company. All rights reserved.

// Licensed under the MIT License (the "License"); you may not use this file except in
// compliance with the License. You may obtain a copy of the License at
// http://opensource.org/licenses/MIT

// Unless required by applicable law or agreed to in writing, software distributed under the License is
// distributed on an "AS IS" basis, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
// either express or implied. See the License for the specific language governing permissions and
// limitations under the License.

#import "MarsXlog.h"

#include <sys/time.h>
#include <string>
#include <vector>

#include "mars/xlog/xlogger_interface.h"
#include "mars/xlog/appender.h"
#include "mars/comm/xlogger/xloggerbase.h"

@implementation MarsXLogConfig

- (instancetype)init {
    self = [super init];
    if (self) {
        _level = MarsXLogLevelInfo;
        _mode = MarsXLogAppenderModeAsync;
        _logdir = @"";
        _nameprefix = @"";
        _pubkey = @"";
        _compressmode = MarsXLogCompressModeZlib;
        _compresslevel = 6;
        _cachedir = nil;
        _cachedays = 0;
    }
    return self;
}

@end

@implementation MarsXlog

+ (uint64_t)newXloggerInstanceWithConfig:(MarsXLogConfig *)config {
    if (!config || config.logdir.length == 0 || config.nameprefix.length == 0) {
        return 0;
    }

    mars::xlog::XLogConfig cpp_config;
    cpp_config.mode_ = (mars::xlog::TAppenderMode)config.mode;
    cpp_config.logdir_ = [config.logdir UTF8String];
    cpp_config.nameprefix_ = [config.nameprefix UTF8String];
    cpp_config.pub_key_ = config.pubkey ? [config.pubkey UTF8String] : "";
    cpp_config.compress_mode_ = (mars::xlog::TCompressMode)config.compressmode;
    cpp_config.compress_level_ = (int)config.compresslevel;
    cpp_config.cachedir_ = config.cachedir ? [config.cachedir UTF8String] : "";
    cpp_config.cache_days_ = (int)config.cachedays;

    return (uint64_t)mars::xlog::NewXloggerInstance(cpp_config, (TLogLevel)config.level);
}

+ (uint64_t)getXloggerInstanceWithNameprefix:(NSString *)nameprefix {
    if (!nameprefix || nameprefix.length == 0) return 0;
    return (uint64_t)mars::xlog::GetXloggerInstance([nameprefix UTF8String]);
}

+ (void)releaseXloggerInstanceWithNameprefix:(NSString *)nameprefix {
    if (!nameprefix || nameprefix.length == 0) return;
    mars::xlog::ReleaseXloggerInstance([nameprefix UTF8String]);
}

+ (void)destroyXlogInstance:(uint64_t)instance {
    mars::xlog::DestroyXlogInstance((uintptr_t)instance);
}

+ (BOOL)hasXlogInstance:(NSString *)nameprefix {
    if (!nameprefix || nameprefix.length == 0) return NO;
    return mars::xlog::HasXlogInstance([nameprefix UTF8String]) ? YES : NO;
}

+ (NSArray<NSString *> *)getAllXlogInstanceNames {
    std::vector<std::string> names = mars::xlog::GetAllXlogInstanceNames();
    NSMutableArray<NSString *> *result = [NSMutableArray arrayWithCapacity:names.size()];
    for (const auto& name : names) {
        [result addObject:[NSString stringWithUTF8String:name.c_str()]];
    }
    return [result copy];
}

+ (void)logWrite:(uint64_t)instance
           level:(MarsXLogLevel)level
             tag:(NSString *)tag
             log:(NSString *)log {
    if (0 == instance) return;

    XLoggerInfo info = XLOGGER_INFO_INITIALIZER;
    gettimeofday(&info.timeval, NULL);
    info.level = (TLogLevel)level;
    info.tag = tag ? [tag UTF8String] : "";
    info.filename = "";
    info.func_name = "";
    info.line = 0;
    info.pid = -1;
    info.tid = -1;
    info.maintid = -1;

    mars::xlog::XloggerWrite((uintptr_t)instance, &info, log ? [log UTF8String] : "");
}

+ (MarsXLogLevel)getLogLevel:(uint64_t)instance {
    return (MarsXLogLevel)mars::xlog::GetLevel((uintptr_t)instance);
}

+ (void)setLogLevel:(uint64_t)instance level:(MarsXLogLevel)level {
    mars::xlog::SetLevel((uintptr_t)instance, (TLogLevel)level);
}

+ (void)setAppenderMode:(uint64_t)instance mode:(MarsXLogAppenderMode)mode {
    mars::xlog::SetAppenderMode((uintptr_t)instance, (mars::xlog::TAppenderMode)mode);
}

+ (void)setConsoleLogOpen:(uint64_t)instance isOpen:(BOOL)isOpen {
    mars::xlog::SetConsoleLogOpen((uintptr_t)instance, isOpen ? true : false);
}

+ (void)setMaxFileSize:(uint64_t)instance maxFileSize:(long)maxFileSize {
    mars::xlog::SetMaxFileSize((uintptr_t)instance, maxFileSize);
}

+ (void)setMaxAliveTime:(uint64_t)instance aliveSeconds:(long)aliveSeconds {
    mars::xlog::SetMaxAliveTime((uintptr_t)instance, aliveSeconds);
}

+ (void)flush:(uint64_t)instance isSync:(BOOL)isSync {
    mars::xlog::Flush((uintptr_t)instance, isSync ? true : false);
}

+ (void)flushAll:(BOOL)isSync {
    mars::xlog::FlushAll(isSync ? true : false);
}

@end
```

- [ ] **Step 2: Commit**

```bash
git add mars/xlog/objc/MarsXlog.mm
git commit -m "feat(xlog): add MarsXlog.mm Objective-C implementation for multi-instance xlog"
```

---

### Task 11: Update CMakeLists.txt

**Files:**
- Modify: `mars/xlog/CMakeLists.txt`

- [ ] **Step 1: Verify APPLE section already picks up all .mm files**

Check lines 47-50:
```cmake
elseif(APPLE)
    file(GLOB SELF_TEMP_SRC_FILES RELATIVE ${PROJECT_SOURCE_DIR} objc/*.mm)
```

The glob `objc/*.mm` already picks up all `.mm` files in the `objc/` directory. Since we created `MarsXlog.mm` in `mars/xlog/objc/`, it will be automatically included. **No CMakeLists.txt change needed.**

- [ ] **Step 2: Commit (skip if no change)**

No commit needed — CMake glob already handles it.

---

## Chunk 4: Cleanup and Verification

### Task 12: Fix all compilation issues

**Files:** Multiple (depends on grep results)

- [ ] **Step 1: Search for direct references to removed globals**

```bash
grep -rn "sg_default_appender\|sg_release_guard\|sg_default_console_log_open\|sg_max_byte_size\|sg_max_alive_time" mars/ --include="*.cc" --include="*.h" --include="*.mm" --include="*.cpp"
```

Expected: no results outside of `appender.cc` (which should have them removed).

- [ ] **Step 2: Search for direct calls to removed functions**

```bash
grep -rn "xlogger_dump\b" mars/ --include="*.cc" --include="*.h" --include="*.mm" --include="*.cpp"
```

If any callers of `xlogger_dump()` exist outside `appender.cc`, they need to be migrated to call `XloggerAppender::Dump()` through an instance. Address each caller individually.

- [ ] **Step 3: Search for old include patterns**

```bash
grep -rn '#include.*"mars/xlog/appender.h"' mars/ --include="*.cc" --include="*.h" --include="*.mm" --include="*.cpp"
```

Verify that files including `appender.h` still compile. They should — the deprecated wrappers are still available.

- [ ] **Step 4: Commit any fixes**

```bash
git add -A
git commit -m "fix(xlog): resolve compilation issues from multi-instance refactor"
```

---

### Task 13: Update export headers

**Files:**
- Modify: `mars/xlog/export_include/xlogger/` directory

- [ ] **Step 1: Check what's currently exported**

```bash
ls mars/xlog/export_include/xlogger/
```

- [ ] **Step 2: Ensure xlog_config.h and xlogger_interface.h are accessible**

If the export_include directory contains copies/symlinks of headers, add `xlog_config.h` there. The exact mechanism depends on how the project manages exported headers (check `mars_utils.py`).

- [ ] **Step 3: Commit**

```bash
git add mars/xlog/export_include/
git commit -m "feat(xlog): update export headers for multi-instance API"
```

---

### Task 14: Final verification commit

- [ ] **Step 1: Run a full grep to confirm no broken references**

```bash
grep -rn "appender_open\|appender_close\|appender_flush\b\|appender_flush_sync\|appender_setmode\b" mars/xlog/src/ --include="*.cc"
```

Expected: no results in `appender.cc` or `xlogger_interface.cc` (only deprecated inline wrappers in `appender.h`).

- [ ] **Step 2: Verify all new APIs are declared and defined**

```bash
grep -n "NewXloggerInstance\|GetXloggerInstance\|ReleaseXloggerInstance\|DestroyXlogInstance\|HasXlogInstance\|GetAllXlogInstanceNames" mars/xlog/xlogger_interface.h mars/xlog/src/xlogger_interface.cc
```

Expected: each function appears once in `.h` (declaration) and once in `.cc` (definition).

- [ ] **Step 3: Create a summary commit if needed**

```bash
git status
```

If there are uncommitted changes:

```bash
git add -A
git commit -m "refactor(xlog): complete multi-instance refactor — all platforms"
```
