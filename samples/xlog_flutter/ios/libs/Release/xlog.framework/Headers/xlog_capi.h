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
 * @file xlog_capi.h
 * @brief Pure C API for mars xlog multi-instance logging.
 *
 * This header provides a C ABI wrapper around the C++ xlog multi-instance API,
 * enabling FFI consumers (Dart, Python, C#, Go, etc.) to use xlog without
 * C++ dependencies.
 *
 * All functions use only C primitive types. String outputs use caller-provided
 * buffers. Errors are expressed through return values (0/NULL = failure).
 */

#ifndef MARS_XLOG_CAPI_H_
#define MARS_XLOG_CAPI_H_

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Platform export macro */
#if defined(_WIN32)
  #ifdef XLOG_CAPI_EXPORT
    #define XLOG_API __declspec(dllexport)
  #else
    #define XLOG_API __declspec(dllimport)
  #endif
#elif defined(__GNUC__) || defined(__clang__)
  #define XLOG_API __attribute__((visibility("default")))
#else
  #define XLOG_API
#endif

/* ---- Enumerations ---- */

typedef enum {
    XLOG_LEVEL_ALL = 0,
    XLOG_LEVEL_VERBOSE = 0,
    XLOG_LEVEL_DEBUG = 1,
    XLOG_LEVEL_INFO = 2,
    XLOG_LEVEL_WARN = 3,
    XLOG_LEVEL_ERROR = 4,
    XLOG_LEVEL_FATAL = 5,
    XLOG_LEVEL_NONE = 6,
} xlog_level_t;

typedef enum {
    XLOG_APPENDER_ASYNC = 0,
    XLOG_APPENDER_SYNC = 1,
} xlog_appender_mode_t;

typedef enum {
    XLOG_COMPRESS_ZLIB = 0,
    XLOG_COMPRESS_ZSTD = 1,
} xlog_compress_mode_t;

/* ---- Configuration ---- */

typedef struct {
    xlog_appender_mode_t  mode;            /**< Async or sync appender mode */
    const char*           logdir;          /**< Log output directory (required) */
    const char*           nameprefix;      /**< Instance identifier (required) */
    const char*           pub_key;         /**< Encryption public key (NULL = no encryption) */
    xlog_compress_mode_t  compress_mode;   /**< Compression algorithm */
    int                   compress_level;  /**< Compression level 0-9 */
    const char*           cachedir;        /**< Cache directory (NULL = disabled) */
    int                   cache_days;      /**< Cache retention days (0 = unlimited) */
} xlog_config_t;

/* ---- Instance lifecycle ---- */

/**
 * Create a new xlog instance.
 * @param config  Instance configuration. logdir and nameprefix are required.
 * @param level   Initial log level.
 * @return Instance handle (non-zero on success, 0 on failure).
 *         If an instance with the same nameprefix already exists, returns
 *         the existing instance handle.
 */
XLOG_API uintptr_t xlog_new_instance(const xlog_config_t* config, xlog_level_t level);

/**
 * Get an existing instance by name prefix.
 * @return Instance handle, or 0 if not found.
 */
XLOG_API uintptr_t xlog_get_instance(const char* nameprefix);

/**
 * Check if an instance with the given name prefix exists.
 * @return 1 if exists, 0 otherwise.
 */
XLOG_API int xlog_has_instance(const char* nameprefix);

/**
 * Release (close and destroy) an instance by name prefix.
 * Uses delayed release to avoid race conditions.
 */
XLOG_API void xlog_release_instance(const char* nameprefix);

/**
 * Destroy an instance by handle.
 * Uses delayed release to avoid race conditions.
 */
XLOG_API void xlog_destroy_instance(uintptr_t instance);

/* ---- Log writing ---- */

/**
 * Write a log message to the specified instance.
 * @param instance  Instance handle (from xlog_new_instance or xlog_get_instance).
 * @param level     Log level for this message.
 * @param tag       Log tag (NULL treated as empty).
 * @param filename  Source filename (NULL treated as empty).
 * @param funcname  Function name (NULL treated as empty).
 * @param line      Source line number (0 if unknown).
 * @param log       Log message text (required, must not be NULL).
 */
XLOG_API void xlog_write(uintptr_t instance, xlog_level_t level,
                          const char* tag, const char* filename,
                          const char* funcname, int line,
                          const char* log);

/* ---- Log level ---- */

/**
 * Check if a log level is enabled for the given instance.
 * @return 1 if enabled, 0 otherwise.
 */
XLOG_API int xlog_is_enabled_for(uintptr_t instance, xlog_level_t level);

/**
 * Get the current log level of the instance.
 */
XLOG_API xlog_level_t xlog_get_level(uintptr_t instance);

/**
 * Set the log level of the instance.
 */
XLOG_API void xlog_set_level(uintptr_t instance, xlog_level_t level);

/* ---- Control ---- */

/**
 * Set the appender mode (async or sync) for the instance.
 */
XLOG_API void xlog_set_appender_mode(uintptr_t instance, xlog_appender_mode_t mode);

/**
 * Enable or disable console log output for the instance.
 * @param is_open  1 to enable, 0 to disable.
 */
XLOG_API void xlog_set_console_log_open(uintptr_t instance, int is_open);

/**
 * Flush the log buffer of the instance.
 * @param is_sync  1 for synchronous flush, 0 for asynchronous.
 */
XLOG_API void xlog_flush(uintptr_t instance, int is_sync);

/**
 * Flush all log instances.
 * @param is_sync  1 for synchronous flush, 0 for asynchronous.
 */
XLOG_API void xlog_flush_all(int is_sync);

/* ---- Path query ---- */

/**
 * Get the current log file path of the instance.
 * @param instance  Instance handle.
 * @param buf       Output buffer for the path string.
 * @param buf_len   Buffer size in bytes.
 * @return 1 on success, 0 on failure.
 */
XLOG_API int xlog_get_log_path(uintptr_t instance, char* buf, unsigned int buf_len);

#ifdef __cplusplus
}
#endif

#endif /* MARS_XLOG_CAPI_H_ */
