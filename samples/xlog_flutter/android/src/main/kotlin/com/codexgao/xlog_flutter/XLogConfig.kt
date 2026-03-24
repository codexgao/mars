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

import com.sun.jna.Structure

/**
 * Configuration for creating an xlog instance.
 * Mirrors xlog_config_t from xlog_capi.h
 */
@Structure.FieldOrder("mode", "logdir", "nameprefix", "pub_key", "compress_mode", "compress_level", "cachedir", "cache_days")
class XLogConfig @JvmOverloads constructor(
    /** Log output directory (required) */
    @JvmField var logdir: String? = null,
    /** Instance name prefix (required) */
    @JvmField var nameprefix: String? = null
) : Structure() {
    /** Appender mode: async (0) or sync (1) */
    @JvmField var mode: Int = XLogAppenderMode.ASYNC.value

    /** Encryption public key (null = no encryption) */
    @JvmField var pub_key: String? = null

    /** Compression mode: zlib (0) or zstd (1) */
    @JvmField var compress_mode: Int = XLogCompressMode.ZLIB.value

    /** Compression level 0-9 */
    @JvmField var compress_level: Int = 0

    /** Cache directory (null = disabled) */
    @JvmField var cachedir: String? = null

    /** Cache retention days (0 = unlimited) */
    @JvmField var cache_days: Int = 0
}
