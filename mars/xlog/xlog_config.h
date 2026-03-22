// Tencent is pleased to support the open source community by making Mars available.
// Copyright (C) 2016 THL A29 Limited, a Tencent company. All rights reserved.

// Licensed under the MIT License (the "License"); you may not use this file except in
// compliance with the License. You may obtain a copy of the License at
// http://opensource.org/licenses/MIT

// Unless required by applicable law or agreed to in writing, software distributed under the License is
// distributed on an "AS IS" basis, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
// either express or implied. See the License for the specific language governing permissions and
// limitations under the License.

#ifndef MARS_XLOG_CONFIG_H_
#define MARS_XLOG_CONFIG_H_

#include <string>

namespace mars {
namespace xlog {

enum TAppenderMode {
    kAppenderAsync,
    kAppenderSync,
};

enum TCompressMode {
    kZlib,
    kZstd,
};

enum TFileIOAction {
    kActionNone = 0,
    kActionSuccess = 1,
    kActionUnnecessary = 2,
    kActionOpenFailed = 3,
    kActionReadFailed = 4,
    kActionWriteFailed = 5,
    kActionCloseFailed = 6,
    kActionRemoveFailed = 7,
};

struct XLogConfig {
    TAppenderMode mode_ = kAppenderAsync;
    std::string logdir_;
    std::string nameprefix_;
    std::string pub_key_;
    TCompressMode compress_mode_ = kZlib;
    int compress_level_ = 6;
    std::string cachedir_;
    int cache_days_ = 0;
};

}  // namespace xlog
}  // namespace mars

#endif  // MARS_XLOG_CONFIG_H_
