#include "xlog_flutter.h"

#include <string>

#include "appender.h"
#include "xlogger/xloggerbase.h"

using mars::xlog::XLogConfig;
using mars::xlog::kAppenderAsync;
using mars::xlog::kAppenderSync;
using mars::xlog::kZlib;
using mars::xlog::kZstd;

void xlog_open(int mode,
               int level,
               const char* logdir,
               const char* nameprefix,
               const char* pub_key,
               int compress_mode,
               const char* cachedir,
               int cache_days) {
    XLogConfig config;
    config.mode_          = (mode == 1) ? kAppenderSync : kAppenderAsync;
    config.logdir_        = logdir ? logdir : "";
    config.nameprefix_    = nameprefix ? nameprefix : "";
    config.pub_key_       = pub_key ? pub_key : "";
    config.compress_mode_ = (compress_mode == 1) ? kZstd : kZlib;
    config.cachedir_      = cachedir ? cachedir : "";
    config.cache_days_    = cache_days;

    mars::xlog::appender_open(config);
    xlogger_SetLevel(static_cast<TLogLevel>(level));
}

void xlog_close(void) {
    mars::xlog::appender_close();
}

void xlog_flush(int is_sync) {
    if (is_sync) {
        mars::xlog::appender_flush_sync();
    } else {
        mars::xlog::appender_flush();
    }
}

void xlog_write(int level,
                const char* tag,
                const char* filename,
                const char* funcname,
                int line,
                const char* message) {
    XLoggerInfo info{};
    info.level     = static_cast<TLogLevel>(level);
    info.tag       = tag;
    info.filename  = filename ? filename : "";
    info.func_name = funcname ? funcname : "";
    info.line      = line;
    gettimeofday(&info.timeval, nullptr);
    info.pid     = xlogger_pid();
    info.tid     = xlogger_tid();
    info.maintid = xlogger_maintid();
    xlogger_Write(&info, message ? message : "");
}

void xlog_set_console_log(int is_open) {
    mars::xlog::appender_set_console_log(is_open != 0);
}

void xlog_set_level(int level) {
    xlogger_SetLevel(static_cast<TLogLevel>(level));
}

void xlog_set_max_file_size(int64_t max_bytes) {
    mars::xlog::appender_set_max_file_size(static_cast<uint64_t>(max_bytes));
}

void xlog_set_max_alive_duration(int64_t max_seconds) {
    mars::xlog::appender_set_max_alive_duration(static_cast<long>(max_seconds));
}
