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

import com.sun.jna.Library
import com.sun.jna.Native

/**
 * JNA interface for xlog C API.
 * Direct mapping to xlog_capi.h functions.
 */
interface XLogLibrary : Library {
    companion object {
        val INSTANCE: XLogLibrary by lazy {
            Native.load("xlog", XLogLibrary::class.java)
        }
    }

    // ==================== Instance Lifecycle ====================

    /**
     * Create a new xlog instance.
     * @param config Instance configuration
     * @param level Initial log level (0-6)
     * @return Instance handle (non-zero on success, 0 on failure)
     */
    fun xlog_new_instance(config: XLogConfig, level: Int): Long

    /**
     * Get an existing instance by name prefix.
     * @param nameprefix Instance name prefix
     * @return Instance handle, or 0 if not found
     */
    fun xlog_get_instance(nameprefix: String): Long

    /**
     * Check if an instance with the given name prefix exists.
     * @param nameprefix Instance name prefix
     * @return 1 if exists, 0 otherwise
     */
    fun xlog_has_instance(nameprefix: String): Int

    /**
     * Release (close and destroy) an instance by name prefix.
     * @param nameprefix Instance name prefix
     */
    fun xlog_release_instance(nameprefix: String)

    /**
     * Destroy an instance by handle.
     * @param instance Instance handle
     */
    fun xlog_destroy_instance(instance: Long)

    // ==================== Log Writing ====================

    /**
     * Write a log message to the specified instance.
     * @param instance Instance handle
     * @param level Log level (0-6)
     * @param tag Log tag (null = empty)
     * @param filename Source filename (null = empty)
     * @param funcname Function name (null = empty)
     * @param line Source line number
     * @param log Log message (required)
     */
    fun xlog_write(
        instance: Long,
        level: Int,
        tag: String?,
        filename: String?,
        funcname: String?,
        line: Int,
        log: String
    )

    // ==================== Log Level ====================

    /**
     * Check if a log level is enabled for the given instance.
     * @param instance Instance handle
     * @param level Log level to check
     * @return 1 if enabled, 0 otherwise
     */
    fun xlog_is_enabled_for(instance: Long, level: Int): Int

    /**
     * Get the current log level of the instance.
     * @param instance Instance handle
     * @return Current log level (0-6)
     */
    fun xlog_get_level(instance: Long): Int

    /**
     * Set the log level of the instance.
     * @param instance Instance handle
     * @param level New log level (0-6)
     */
    fun xlog_set_level(instance: Long, level: Int)

    // ==================== Control ====================

    /**
     * Set the appender mode (async or sync) for the instance.
     * @param instance Instance handle
     * @param mode Appender mode (0=async, 1=sync)
     */
    fun xlog_set_appender_mode(instance: Long, mode: Int)

    /**
     * Enable or disable console log output for the instance.
     * @param instance Instance handle
     * @param isOpen 1 to enable, 0 to disable
     */
    fun xlog_set_console_log_open(instance: Long, isOpen: Int)

    /**
     * Flush the log buffer of the instance.
     * @param instance Instance handle
     * @param isSync 1 for synchronous flush, 0 for asynchronous
     */
    fun xlog_flush(instance: Long, isSync: Int)

    /**
     * Flush all log instances.
     * @param isSync 1 for synchronous flush, 0 for asynchronous
     */
    fun xlog_flush_all(isSync: Int)

    // ==================== Path Query ====================

    /**
     * Get the current log file path of the instance.
     * @param instance Instance handle
     * @param buf Output buffer for the path string
     * @param bufLen Buffer size in bytes
     * @return 1 on success, 0 on failure
     */
    fun xlog_get_log_path(instance: Long, buf: ByteArray, bufLen: Int): Int
}
