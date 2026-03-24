// Tencent is pleased to support the open source community by making Mars available.
// Copyright (C) 2016 THL A29 Limited, a Tencent company. All rights reserved.

// Licensed under the MIT License (the "License"); you may not use this file except in
// compliance with the License. You may obtain a copy of the License at
// http://opensource.org/licenses/MIT

// Unless required by applicable law or agreed to in writing, software distributed under the License is
// distributed on an "AS IS" basis, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
// either express or implied. See the License for the specific language governing permissions and
// limitations under the License.

package com.codexgao.xlog_flutter

/**
 * XLog Kotlin API - JNA wrapper for xlog C API.
 *
 * Usage example:
 * ```kotlin
 * val config = XLogConfig("/path/to/logs", "myapp")
 * val instance = XLog.newInstance(config, XLogLevel.DEBUG)
 *
 * XLog.i(instance, "TAG", "Application started")
 *
 * XLog.flush(instance, sync = true)
 * XLog.releaseInstance("myapp")
 * ```
 */
object XLog {
    // JNA automatically loads the native library via XLogLibrary.INSTANCE

    // ==================== Instance Lifecycle ====================

    /**
     * Create a new xlog instance.
     *
     * @param config Instance configuration (logdir and nameprefix required)
     * @param level Initial log level (default: DEBUG)
     * @return Instance handle (non-zero on success, 0 on failure)
     */
    @JvmStatic
    @JvmOverloads
    fun newInstance(config: XLogConfig, level: XLogLevel = XLogLevel.DEBUG): Long {
        return XLogLibrary.INSTANCE.xlog_new_instance(config, level.value)
    }

    /**
     * Get an existing instance by name prefix.
     *
     * @param nameprefix Instance name prefix
     * @return Instance handle, or 0 if not found
     */
    @JvmStatic
    fun getInstance(nameprefix: String): Long {
        return XLogLibrary.INSTANCE.xlog_get_instance(nameprefix)
    }

    /**
     * Check if an instance with the given name prefix exists.
     *
     * @param nameprefix Instance name prefix
     * @return true if exists, false otherwise
     */
    @JvmStatic
    fun hasInstance(nameprefix: String): Boolean {
        return XLogLibrary.INSTANCE.xlog_has_instance(nameprefix) != 0
    }

    /**
     * Release (close and destroy) an instance by name prefix.
     *
     * @param nameprefix Instance name prefix
     */
    @JvmStatic
    fun releaseInstance(nameprefix: String) {
        XLogLibrary.INSTANCE.xlog_release_instance(nameprefix)
    }

    /**
     * Destroy an instance by handle.
     *
     * @param instance Instance handle
     */
    @JvmStatic
    fun destroyInstance(instance: Long) {
        XLogLibrary.INSTANCE.xlog_destroy_instance(instance)
    }

    // ==================== Log Writing ====================

    /**
     * Write a log message to the specified instance.
     *
     * @param instance Instance handle
     * @param level Log level
     * @param tag Log tag
     * @param message Log message
     * @param filename Source filename (optional)
     * @param funcname Function name (optional)
     * @param line Source line number (optional)
     */
    @JvmStatic
    @JvmOverloads
    fun write(
        instance: Long,
        level: XLogLevel,
        tag: String,
        message: String,
        filename: String? = null,
        funcname: String? = null,
        line: Int = 0
    ) {
        if (instance == 0L) return
        XLogLibrary.INSTANCE.xlog_write(
            instance, level.value, tag, filename, funcname, line, message
        )
    }

    /**
     * Write a verbose-level log message.
     */
    @JvmStatic
    fun v(instance: Long, tag: String, message: String) {
        write(instance, XLogLevel.VERBOSE, tag, message)
    }

    /**
     * Write a debug-level log message.
     */
    @JvmStatic
    fun d(instance: Long, tag: String, message: String) {
        write(instance, XLogLevel.DEBUG, tag, message)
    }

    /**
     * Write an info-level log message.
     */
    @JvmStatic
    fun i(instance: Long, tag: String, message: String) {
        write(instance, XLogLevel.INFO, tag, message)
    }

    /**
     * Write a warning-level log message.
     */
    @JvmStatic
    fun w(instance: Long, tag: String, message: String) {
        write(instance, XLogLevel.WARN, tag, message)
    }

    /**
     * Write an error-level log message.
     */
    @JvmStatic
    fun e(instance: Long, tag: String, message: String) {
        write(instance, XLogLevel.ERROR, tag, message)
    }

    /**
     * Write a fatal-level log message.
     */
    @JvmStatic
    fun f(instance: Long, tag: String, message: String) {
        write(instance, XLogLevel.FATAL, tag, message)
    }

    // ==================== Log Level ====================

    /**
     * Check if a log level is enabled for the given instance.
     *
     * @param instance Instance handle
     * @param level Log level to check
     * @return true if enabled, false otherwise
     */
    @JvmStatic
    fun isEnabledFor(instance: Long, level: XLogLevel): Boolean {
        return XLogLibrary.INSTANCE.xlog_is_enabled_for(instance, level.value) != 0
    }

    /**
     * Get the current log level of the instance.
     *
     * @param instance Instance handle
     * @return Current log level
     */
    @JvmStatic
    fun getLevel(instance: Long): XLogLevel {
        return XLogLevel.fromValue(XLogLibrary.INSTANCE.xlog_get_level(instance))
    }

    /**
     * Set the log level of the instance.
     *
     * @param instance Instance handle
     * @param level New log level
     */
    @JvmStatic
    fun setLevel(instance: Long, level: XLogLevel) {
        XLogLibrary.INSTANCE.xlog_set_level(instance, level.value)
    }

    // ==================== Control ====================

    /**
     * Set the appender mode (async or sync) for the instance.
     *
     * @param instance Instance handle
     * @param mode Appender mode
     */
    @JvmStatic
    fun setAppenderMode(instance: Long, mode: XLogAppenderMode) {
        XLogLibrary.INSTANCE.xlog_set_appender_mode(instance, mode.value)
    }

    /**
     * Enable or disable console log output for the instance.
     *
     * @param instance Instance handle
     * @param isOpen true to enable, false to disable
     */
    @JvmStatic
    fun setConsoleLogOpen(instance: Long, isOpen: Boolean) {
        XLogLibrary.INSTANCE.xlog_set_console_log_open(instance, if (isOpen) 1 else 0)
    }

    /**
     * Flush the log buffer of the instance.
     *
     * @param instance Instance handle
     * @param sync true for synchronous flush, false for asynchronous
     */
    @JvmStatic
    @JvmOverloads
    fun flush(instance: Long, sync: Boolean = false) {
        XLogLibrary.INSTANCE.xlog_flush(instance, if (sync) 1 else 0)
    }

    /**
     * Flush all log instances.
     *
     * @param sync true for synchronous flush, false for asynchronous
     */
    @JvmStatic
    @JvmOverloads
    fun flushAll(sync: Boolean = false) {
        XLogLibrary.INSTANCE.xlog_flush_all(if (sync) 1 else 0)
    }

    // ==================== Path Query ====================

    /**
     * Get the current log file path of the instance.
     *
     * @param instance Instance handle
     * @return Log file path, or null if unavailable
     */
    @JvmStatic
    fun getLogPath(instance: Long): String? {
        val buffer = ByteArray(1024)
        return if (XLogLibrary.INSTANCE.xlog_get_log_path(instance, buffer, buffer.size) != 0) {
            buffer.decodeToString().trimEnd('\u0000')
        } else null
    }
}
