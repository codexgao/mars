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
 * @Author: garryyan
 * @LastEditors: garryyan
 * @Date: 2019-03-05 15:10:24
 * @LastEditTime: 2019-03-05 15:10:50
 */

#include "mars/xlog/xlogger_interface.h"

#include <functional>
#include <map>

#include "mars/comm/bootrun.h"
#include "mars/comm/thread/lock.h"
#include "mars/comm/thread/mutex.h"
#include "mars/comm/xlogger/xlogger_category.h"
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

// Resolve instance_ptr: when 0, look up "default" instance from map.
// Caller MUST hold GetGlobalMutex() or guarantee thread-safety externally.
static uintptr_t ResolveInstance(uintptr_t _instance_ptr) {
    if (0 != _instance_ptr)
        return _instance_ptr;
    auto it = GetGlobalInstanceMap().find("default");
    if (it != GetGlobalInstanceMap().end()) {
        return reinterpret_cast<uintptr_t>(it->second);
    }
    return 0;
}

// Global xlogger callback: forwards xlogger_Write() / xlogger2() macro calls
// to the "default" instance's appender.
static void DefaultInstanceAppenderCallback(const XLoggerInfo* _info, const char* _log) {
    ScopedLock lock(GetGlobalMutex());
    auto it = GetGlobalInstanceMap().find("default");
    if (it == GetGlobalInstanceMap().end()) {
        return;
    }
    XloggerCategory* category = it->second;
    lock.unlock();
    category->Write(_info, _log);
}

// Process exit cleanup: flush all instances and release.
static void ReleaseAllInstances() {
    ScopedLock lock(GetGlobalMutex());
    auto& xmap = GetGlobalInstanceMap();

    // First pass: flush all synchronously
    for (auto it = xmap.begin(); it != xmap.end(); ++it) {
        XloggerCategory* category = it->second;
        XloggerAppender* appender = reinterpret_cast<XloggerAppender*>(category->GetAppender());
        appender->FlushSync();
    }

    // Second pass: close and release
    for (auto it = xmap.begin(); it != xmap.end(); ++it) {
        XloggerCategory* category = it->second;
        XloggerAppender* appender = reinterpret_cast<XloggerAppender*>(category->GetAppender());
        appender->Close();
        // Note: at process exit we don't delay-release, just close to flush buffers.
        // Actual memory is allowed to leak to avoid use-after-free from other threads at exit.
    }
    xmap.clear();
}

BOOT_RUN_EXIT(ReleaseAllInstances);

uintptr_t NewXloggerInstance(const XLogConfig& _config, TLogLevel _level) {
    if (_config.logdir_.empty() || _config.nameprefix_.empty()) {
        return 0;
    }

    ScopedLock lock(GetGlobalMutex());
    auto it = GetGlobalInstanceMap().find(_config.nameprefix_);
    if (it != GetGlobalInstanceMap().end()) {
        return reinterpret_cast<uintptr_t>(it->second);
    }

    XloggerAppender* appender = XloggerAppender::NewInstance(_config, 0);

    using namespace std::placeholders;
    XloggerCategory* category = XloggerCategory::NewInstance(reinterpret_cast<uintptr_t>(appender),
                                                             std::bind(&XloggerAppender::Write, appender, _1, _2));
    category->SetLevel(_level);
    GetGlobalInstanceMap()[_config.nameprefix_] = category;

    // When creating the "default" instance, register global xlogger callback
    if (_config.nameprefix_ == "default") {
        xlogger_SetAppender(&DefaultInstanceAppenderCallback);
        xlogger_SetLevel(_level);
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

    // When releasing the "default" instance, unregister global xlogger callback
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
    if (0 == _instance)
        return;

    ScopedLock lock(GetGlobalMutex());
    auto& xmap = GetGlobalInstanceMap();
    for (auto it = xmap.begin(); it != xmap.end(); ++it) {
        if (reinterpret_cast<uintptr_t>(it->second) == _instance) {
            // If this is the "default" instance, unregister global callback
            if (it->first == "default") {
                xlogger_SetAppender(nullptr);
            }

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

bool HasXlogInstance(const char* _nameprefix) {
    if (nullptr == _nameprefix)
        return false;

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

void XloggerWrite(uintptr_t _instance_ptr, const XLoggerInfo* _info, const char* _log) {
    ScopedLock lock(GetGlobalMutex());
    uintptr_t resolved = ResolveInstance(_instance_ptr);
    if (0 == resolved)
        return;
    XloggerCategory* category = reinterpret_cast<XloggerCategory*>(resolved);
    lock.unlock();
    category->Write(_info, _log);
}

bool IsEnabledFor(uintptr_t _instance_ptr, TLogLevel _level) {
    ScopedLock lock(GetGlobalMutex());
    uintptr_t resolved = ResolveInstance(_instance_ptr);
    if (0 == resolved)
        return false;
    XloggerCategory* category = reinterpret_cast<XloggerCategory*>(resolved);
    return category->IsEnabledFor(_level);
}

TLogLevel GetLevel(uintptr_t _instance_ptr) {
    ScopedLock lock(GetGlobalMutex());
    uintptr_t resolved = ResolveInstance(_instance_ptr);
    if (0 == resolved)
        return kLevelNone;
    XloggerCategory* category = reinterpret_cast<XloggerCategory*>(resolved);
    return category->GetLevel();
}

void SetLevel(uintptr_t _instance_ptr, TLogLevel _level) {
    ScopedLock lock(GetGlobalMutex());
    uintptr_t resolved = ResolveInstance(_instance_ptr);
    if (0 == resolved)
        return;
    XloggerCategory* category = reinterpret_cast<XloggerCategory*>(resolved);
    category->SetLevel(_level);
}

void SetAppenderMode(uintptr_t _instance_ptr, TAppenderMode _mode) {
    ScopedLock lock(GetGlobalMutex());
    uintptr_t resolved = ResolveInstance(_instance_ptr);
    if (0 == resolved)
        return;
    XloggerCategory* category = reinterpret_cast<XloggerCategory*>(resolved);
    XloggerAppender* appender = reinterpret_cast<XloggerAppender*>(category->GetAppender());
    lock.unlock();
    appender->SetMode(_mode);
}

void Flush(uintptr_t _instance_ptr, bool _is_sync) {
    ScopedLock lock(GetGlobalMutex());
    uintptr_t resolved = ResolveInstance(_instance_ptr);
    if (0 == resolved)
        return;
    XloggerCategory* category = reinterpret_cast<XloggerCategory*>(resolved);
    XloggerAppender* appender = reinterpret_cast<XloggerAppender*>(category->GetAppender());
    lock.unlock();
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
            appenders.push_back(reinterpret_cast<XloggerAppender*>(category->GetAppender()));
        }
    }
    for (auto* appender : appenders) {
        _is_sync ? appender->FlushSync() : appender->Flush();
    }
}

void SetConsoleLogOpen(uintptr_t _instance_ptr, bool _is_open) {
    ScopedLock lock(GetGlobalMutex());
    uintptr_t resolved = ResolveInstance(_instance_ptr);
    if (0 == resolved)
        return;
    XloggerCategory* category = reinterpret_cast<XloggerCategory*>(resolved);
    XloggerAppender* appender = reinterpret_cast<XloggerAppender*>(category->GetAppender());
    lock.unlock();
    appender->SetConsoleLog(_is_open);
}

void SetMaxFileSize(uintptr_t _instance_ptr, long _max_file_size) {
    ScopedLock lock(GetGlobalMutex());
    uintptr_t resolved = ResolveInstance(_instance_ptr);
    if (0 == resolved)
        return;
    XloggerCategory* category = reinterpret_cast<XloggerCategory*>(resolved);
    XloggerAppender* appender = reinterpret_cast<XloggerAppender*>(category->GetAppender());
    lock.unlock();
    appender->SetMaxFileSize(_max_file_size);
}

void SetMaxAliveTime(uintptr_t _instance_ptr, long _alive_seconds) {
    ScopedLock lock(GetGlobalMutex());
    uintptr_t resolved = ResolveInstance(_instance_ptr);
    if (0 == resolved)
        return;
    XloggerCategory* category = reinterpret_cast<XloggerCategory*>(resolved);
    XloggerAppender* appender = reinterpret_cast<XloggerAppender*>(category->GetAppender());
    lock.unlock();
    appender->SetMaxAliveDuration(_alive_seconds);
}

bool GetFilePathFromTimespan(uintptr_t _instance_ptr,
                             int _timespan,
                             const char* _prefix,
                             std::vector<std::string>& _filepath_vec) {
    ScopedLock lock(GetGlobalMutex());
    uintptr_t resolved = ResolveInstance(_instance_ptr);
    if (0 == resolved)
        return false;
    XloggerCategory* category = reinterpret_cast<XloggerCategory*>(resolved);
    XloggerAppender* appender = reinterpret_cast<XloggerAppender*>(category->GetAppender());
    lock.unlock();
    return appender->GetfilepathFromTimespan(_timespan, _prefix, _filepath_vec);
}

bool MakeLogFileName(uintptr_t _instance_ptr,
                     int _timespan,
                     const char* _prefix,
                     std::vector<std::string>& _filepath_vec) {
    ScopedLock lock(GetGlobalMutex());
    uintptr_t resolved = ResolveInstance(_instance_ptr);
    if (0 == resolved)
        return false;
    XloggerCategory* category = reinterpret_cast<XloggerCategory*>(resolved);
    XloggerAppender* appender = reinterpret_cast<XloggerAppender*>(category->GetAppender());
    lock.unlock();
    return appender->MakeLogfileName(_timespan, _prefix, _filepath_vec);
}

bool GetCurrentLogPath(uintptr_t _instance_ptr, char* _log_path, unsigned int _len) {
    ScopedLock lock(GetGlobalMutex());
    uintptr_t resolved = ResolveInstance(_instance_ptr);
    if (0 == resolved)
        return false;
    XloggerCategory* category = reinterpret_cast<XloggerCategory*>(resolved);
    XloggerAppender* appender = reinterpret_cast<XloggerAppender*>(category->GetAppender());
    lock.unlock();
    return appender->GetCurrentLogPath(_log_path, _len);
}

bool GetCurrentLogCachePath(uintptr_t _instance_ptr, char* _log_path, unsigned int _len) {
    ScopedLock lock(GetGlobalMutex());
    uintptr_t resolved = ResolveInstance(_instance_ptr);
    if (0 == resolved)
        return false;
    XloggerCategory* category = reinterpret_cast<XloggerCategory*>(resolved);
    XloggerAppender* appender = reinterpret_cast<XloggerAppender*>(category->GetAppender());
    lock.unlock();
    return appender->GetCurrentLogCachePath(_log_path, _len);
}

}  // namespace xlog
}  // namespace mars
