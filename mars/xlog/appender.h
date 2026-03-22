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

#include "xlog_config.h"

// Cross-platform deprecated attribute macro
#if defined(__GNUC__) || defined(__clang__)
#define XLOG_DEPRECATED __attribute__((deprecated("Use xlogger_interface.h multi-instance API instead")))
#elif defined(_MSC_VER)
#define XLOG_DEPRECATED __declspec(deprecated("Use xlogger_interface.h multi-instance API instead"))
#else
#define XLOG_DEPRECATED
#endif

namespace mars {
namespace xlog {

#ifdef __APPLE__
enum TConsoleFun {
    kConsolePrintf,
    kConsoleNSLog,
    kConsoleOSLog,
};

void appender_set_console_fun(TConsoleFun _fun);
#endif

void appender_oneshot_flush(const XLogConfig& _config, TFileIOAction* _result);

}  // namespace xlog
}  // namespace mars

// Include xlogger_interface.h for deprecated wrappers to call the new API.
// This must come after the mars::xlog namespace block above to avoid circular issues.
#include "xlogger_interface.h"

namespace mars {
namespace xlog {

// ============================================================================
// Deprecated compatibility wrappers
// All below forward to the multi-instance API via the "default" instance.
// Callers should migrate to NewXloggerInstance() / xlogger_interface.h API.
// ============================================================================

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
    if (inst)
        SetAppenderMode(inst, _mode);
}

XLOG_DEPRECATED
inline bool appender_get_current_log_path(char* _log_path, unsigned int _len) {
    uintptr_t inst = GetXloggerInstance("default");
    if (inst)
        return GetCurrentLogPath(inst, _log_path, _len);
    return false;
}

XLOG_DEPRECATED
inline bool appender_get_current_log_cache_path(char* _logPath, unsigned int _len) {
    uintptr_t inst = GetXloggerInstance("default");
    if (inst)
        return GetCurrentLogCachePath(inst, _logPath, _len);
    return false;
}

XLOG_DEPRECATED
inline void appender_set_console_log(bool _is_open) {
    uintptr_t inst = GetXloggerInstance("default");
    if (inst)
        SetConsoleLogOpen(inst, _is_open);
}

XLOG_DEPRECATED
inline void appender_set_max_file_size(uint64_t _max_byte_size) {
    uintptr_t inst = GetXloggerInstance("default");
    if (inst)
        SetMaxFileSize(inst, _max_byte_size);
}

XLOG_DEPRECATED
inline void appender_set_max_alive_duration(long _max_time) {
    uintptr_t inst = GetXloggerInstance("default");
    if (inst)
        SetMaxAliveTime(inst, _max_time);
}

XLOG_DEPRECATED
inline bool appender_getfilepath_from_timespan(int _timespan,
                                               const char* _prefix,
                                               std::vector<std::string>& _filepath_vec) {
    uintptr_t inst = GetXloggerInstance("default");
    if (inst)
        return GetFilePathFromTimespan(inst, _timespan, _prefix, _filepath_vec);
    return false;
}

XLOG_DEPRECATED
inline bool appender_make_logfile_name(int _timespan,
                                       const char* _prefix,
                                       std::vector<std::string>& _filepath_vec) {
    uintptr_t inst = GetXloggerInstance("default");
    if (inst)
        return MakeLogFileName(inst, _timespan, _prefix, _filepath_vec);
    return false;
}

}  // namespace xlog
}  // namespace mars

#endif /* APPENDER_H_ */
