#ifndef XLOG_FLUTTER_H_
#define XLOG_FLUTTER_H_

#include <stdint.h>

#if _WIN32
#define FFI_PLUGIN_EXPORT __declspec(dllexport)
#else
#define FFI_PLUGIN_EXPORT __attribute__((visibility("default"))) __attribute__((used))
#endif

#ifdef __cplusplus
extern "C" {
#endif

// Open xlog appender.
// mode: 0=async, 1=sync
// level: 0=verbose, 1=debug, 2=info, 3=warn, 4=error, 5=fatal, 6=none
// compress_mode: 0=zlib, 1=zstd
// logdir, nameprefix, pub_key, cachedir: UTF-8 strings; pub_key/cachedir may be NULL/empty
// cache_days: 0 = no cache limit
FFI_PLUGIN_EXPORT void xlog_open(int mode,
                                 int level,
                                 const char* logdir,
                                 const char* nameprefix,
                                 const char* pub_key,
                                 int compress_mode,
                                 const char* cachedir,
                                 int cache_days);

FFI_PLUGIN_EXPORT void xlog_close(void);

// is_sync: 0=async flush, 1=sync flush (blocks until flushed)
FFI_PLUGIN_EXPORT void xlog_flush(int is_sync);

// Write a log entry.
// level: same values as xlog_open's level param
// tag, filename, funcname, message: UTF-8 strings; filename/funcname may be NULL
// line: source line number (0 if unknown)
FFI_PLUGIN_EXPORT void xlog_write(int level,
                                  const char* tag,
                                  const char* filename,
                                  const char* funcname,
                                  int line,
                                  const char* message);

FFI_PLUGIN_EXPORT void xlog_set_console_log(int is_open);
FFI_PLUGIN_EXPORT void xlog_set_level(int level);

// max_bytes: 0 = no file size limit (default)
FFI_PLUGIN_EXPORT void xlog_set_max_file_size(int64_t max_bytes);

// max_seconds: max alive duration in seconds (default: 10 days = 864000)
FFI_PLUGIN_EXPORT void xlog_set_max_alive_duration(int64_t max_seconds);

#ifdef __cplusplus
}
#endif

#endif  // XLOG_FLUTTER_H_
