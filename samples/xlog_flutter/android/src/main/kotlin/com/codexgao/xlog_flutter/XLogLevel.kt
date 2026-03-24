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
 * Log level definitions for xlog.
 */
enum class XLogLevel(val value: Int) {
    /** All log levels */
    ALL(0),
    /** Verbose level */
    VERBOSE(0),
    /** Debug level */
    DEBUG(1),
    /** Info level */
    INFO(2),
    /** Warning level */
    WARN(3),
    /** Error level */
    ERROR(4),
    /** Fatal level */
    FATAL(5),
    /** No logging */
    NONE(6);

    companion object {
        fun fromValue(value: Int): XLogLevel {
            return values().find { it.value == value } ?: DEBUG
        }
    }
}
