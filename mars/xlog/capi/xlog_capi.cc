// Tencent is pleased to support the open source community by making Mars available.
// Copyright (C) 2016 THL A29 Limited, a Tencent company. All rights reserved.

// Licensed under the MIT License (the "License"); you may not use this file except in
// compliance with the License. You may obtain a copy of the License at
// http://opensource.org/licenses/MIT

// Unless required by applicable law or agreed to in writing, software distributed under the License is
// distributed on an "AS IS" basis, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
// either express or implied. See the License for the specific language governing permissions and
// limitations under the License.

/**
 * @file xlog_capi.cc
 * @brief C ABI wrapper implementation for mars xlog multi-instance API.
 */

#include "mars/xlog/capi/xlog_capi.h"

#include <string.h>

#ifdef _WIN32
#include <process.h>
#include <windows.h>
#else
#include <sys/time.h>
#include <unistd.h>
#include <pthread.h>
#endif

#include <string>

#include "mars/xlog/xlogger_interface.h"
#include "mars/comm/xlogger/xloggerbase.h"

// Helper: NULL-safe C string to std::string
static inline std::string SafeStr(const char* s) {
    return s ? std::string(s) : std::string();
}

// Helper: get current time as struct timeval
static inline struct timeval GetTimeOfDay() {
    struct timeval tv = {0, 0};
#ifdef _WIN32
    FILETIME ft;
    GetSystemTimeAsFileTime(&ft);
    ULARGE_INTEGER uli;
    uli.LowPart = ft.dwLowDateTime;
    uli.HighPart = ft.dwHighDateTime;
    // Convert from 100-ns intervals since 1601-01-01 to Unix epoch (1970-01-01)
    uli.QuadPart -= 116444736000000000ULL;
    tv.tv_sec = (long)(uli.QuadPart / 10000000ULL);
    tv.tv_usec = (long)((uli.QuadPart % 10000000ULL) / 10);
#else
    gettimeofday(&tv, nullptr);
#endif
    return tv;
}

// Helper: get current process ID
static inline intmax_t GetCurrentPid() {
#ifdef _WIN32
    return (intmax_t)_getpid();
#else
    return (intmax_t)getpid();
#endif
}

// Helper: get current thread ID
static inline intmax_t GetCurrentTid() {
#ifdef _WIN32
    return (intmax_t)GetCurrentThreadId();
#else
    return (intmax_t)pthread_self();
#endif
}

extern "C" {

uintptr_t xlog_new_instance(const xlog_config_t* config, xlog_level_t level) {
    if (!config || !config->logdir || !config->nameprefix) {
        return 0;
    }

    mars::xlog::XLogConfig cpp_config;
    cpp_config.mode_ = static_cast<mars::xlog::TAppenderMode>(config->mode);
    cpp_config.logdir_ = config->logdir;
    cpp_config.nameprefix_ = config->nameprefix;
    cpp_config.pub_key_ = SafeStr(config->pub_key);
    cpp_config.compress_mode_ = static_cast<mars::xlog::TCompressMode>(config->compress_mode);
    cpp_config.compress_level_ = config->compress_level;
    cpp_config.cachedir_ = SafeStr(config->cachedir);
    cpp_config.cache_days_ = config->cache_days;

    return mars::xlog::NewXloggerInstance(cpp_config, static_cast<TLogLevel>(level));
}

uintptr_t xlog_get_instance(const char* nameprefix) {
    if (!nameprefix) return 0;
    return mars::xlog::GetXloggerInstance(nameprefix);
}

int xlog_has_instance(const char* nameprefix) {
    if (!nameprefix) return 0;
    return mars::xlog::HasXlogInstance(nameprefix) ? 1 : 0;
}

void xlog_release_instance(const char* nameprefix) {
    if (!nameprefix) return;
    mars::xlog::ReleaseXloggerInstance(nameprefix);
}

void xlog_destroy_instance(uintptr_t instance) {
    mars::xlog::DestroyXlogInstance(instance);
}

void xlog_write(uintptr_t instance, xlog_level_t level,
                const char* tag, const char* filename,
                const char* funcname, int line,
                const char* log) {
    if (0 == instance || !log) return;

    XLoggerInfo info = XLOGGER_INFO_INITIALIZER;
    info.level = static_cast<TLogLevel>(level);
    info.tag = tag ? tag : "";
    info.filename = filename ? filename : "";
    info.func_name = funcname ? funcname : "";
    info.line = line;
    info.timeval = GetTimeOfDay();
    info.pid = GetCurrentPid();
    info.tid = GetCurrentTid();
    info.maintid = 0;
    info.traceLog = 0;

    mars::xlog::XloggerWrite(instance, &info, log);
}

int xlog_is_enabled_for(uintptr_t instance, xlog_level_t level) {
    return mars::xlog::IsEnabledFor(instance, static_cast<TLogLevel>(level)) ? 1 : 0;
}

xlog_level_t xlog_get_level(uintptr_t instance) {
    return static_cast<xlog_level_t>(mars::xlog::GetLevel(instance));
}

void xlog_set_level(uintptr_t instance, xlog_level_t level) {
    mars::xlog::SetLevel(instance, static_cast<TLogLevel>(level));
}

void xlog_set_appender_mode(uintptr_t instance, xlog_appender_mode_t mode) {
    mars::xlog::SetAppenderMode(instance, static_cast<mars::xlog::TAppenderMode>(mode));
}

void xlog_set_console_log_open(uintptr_t instance, int is_open) {
    mars::xlog::SetConsoleLogOpen(instance, is_open != 0);
}

void xlog_flush(uintptr_t instance, int is_sync) {
    mars::xlog::Flush(instance, is_sync != 0);
}

void xlog_flush_all(int is_sync) {
    mars::xlog::FlushAll(is_sync != 0);
}

int xlog_get_log_path(uintptr_t instance, char* buf, unsigned int buf_len) {
    if (!buf || buf_len == 0) return 0;
    return mars::xlog::GetCurrentLogPath(instance, buf, buf_len) ? 1 : 0;
}

}  // extern "C"
