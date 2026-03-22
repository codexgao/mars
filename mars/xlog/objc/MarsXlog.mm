// Tencent is pleased to support the open source community by making Mars available.
// Copyright (C) 2016 THL A29 Limited, a Tencent company. All rights reserved.

// Licensed under the MIT License (the "License"); you may not use this file except in
// compliance with the License. You may obtain a copy of the License at
// http://opensource.org/licenses/MIT

// Unless required by applicable law or agreed to in writing, software distributed under the License is
// distributed on an "AS IS" basis, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
// either express or implied. See the License for the specific language governing permissions and
// limitations under the License.

#import "MarsXlog.h"

#include <sys/time.h>
#include <string>
#include <vector>

#include "mars/xlog/xlogger_interface.h"
#include "mars/xlog/xlog_config.h"
#include "mars/comm/xlogger/xloggerbase.h"

@implementation MarsXLogConfig

- (instancetype)init {
    self = [super init];
    if (self) {
        _level = MarsXLogLevelInfo;
        _mode = MarsXLogAppenderModeAsync;
        _logdir = @"";
        _nameprefix = @"";
        _pubkey = @"";
        _compressmode = MarsXLogCompressModeZlib;
        _compresslevel = 6;
        _cachedir = nil;
        _cachedays = 0;
    }
    return self;
}

@end

@implementation MarsXlog

+ (uint64_t)newXloggerInstanceWithConfig:(MarsXLogConfig *)config {
    if (!config || config.logdir.length == 0 || config.nameprefix.length == 0) {
        return 0;
    }

    mars::xlog::XLogConfig cpp_config;
    cpp_config.mode_ = (mars::xlog::TAppenderMode)config.mode;
    cpp_config.logdir_ = [config.logdir UTF8String];
    cpp_config.nameprefix_ = [config.nameprefix UTF8String];
    cpp_config.pub_key_ = config.pubkey ? [config.pubkey UTF8String] : "";
    cpp_config.compress_mode_ = (mars::xlog::TCompressMode)config.compressmode;
    cpp_config.compress_level_ = (int)config.compresslevel;
    cpp_config.cachedir_ = config.cachedir ? [config.cachedir UTF8String] : "";
    cpp_config.cache_days_ = (int)config.cachedays;

    return (uint64_t)mars::xlog::NewXloggerInstance(cpp_config, (TLogLevel)config.level);
}

+ (uint64_t)getXloggerInstanceWithNameprefix:(NSString *)nameprefix {
    if (!nameprefix || nameprefix.length == 0) return 0;
    return (uint64_t)mars::xlog::GetXloggerInstance([nameprefix UTF8String]);
}

+ (void)releaseXloggerInstanceWithNameprefix:(NSString *)nameprefix {
    if (!nameprefix || nameprefix.length == 0) return;
    mars::xlog::ReleaseXloggerInstance([nameprefix UTF8String]);
}

+ (void)destroyXlogInstance:(uint64_t)instance {
    mars::xlog::DestroyXlogInstance((uintptr_t)instance);
}

+ (BOOL)hasXlogInstance:(NSString *)nameprefix {
    if (!nameprefix || nameprefix.length == 0) return NO;
    return mars::xlog::HasXlogInstance([nameprefix UTF8String]) ? YES : NO;
}

+ (NSArray<NSString *> *)getAllXlogInstanceNames {
    std::vector<std::string> names = mars::xlog::GetAllXlogInstanceNames();
    NSMutableArray<NSString *> *result = [NSMutableArray arrayWithCapacity:names.size()];
    for (const auto& name : names) {
        [result addObject:[NSString stringWithUTF8String:name.c_str()]];
    }
    return [result copy];
}

+ (void)logWrite:(uint64_t)instance
           level:(MarsXLogLevel)level
             tag:(NSString *)tag
             log:(NSString *)log {
    if (0 == instance) return;

    XLoggerInfo info = XLOGGER_INFO_INITIALIZER;
    gettimeofday(&info.timeval, NULL);
    info.level = (TLogLevel)level;
    info.tag = tag ? [tag UTF8String] : "";
    info.filename = "";
    info.func_name = "";
    info.line = 0;
    info.pid = -1;
    info.tid = -1;
    info.maintid = -1;

    mars::xlog::XloggerWrite((uintptr_t)instance, &info, log ? [log UTF8String] : "");
}

+ (MarsXLogLevel)getLogLevel:(uint64_t)instance {
    return (MarsXLogLevel)mars::xlog::GetLevel((uintptr_t)instance);
}

+ (void)setLogLevel:(uint64_t)instance level:(MarsXLogLevel)level {
    mars::xlog::SetLevel((uintptr_t)instance, (TLogLevel)level);
}

+ (void)setAppenderMode:(uint64_t)instance mode:(MarsXLogAppenderMode)mode {
    mars::xlog::SetAppenderMode((uintptr_t)instance, (mars::xlog::TAppenderMode)mode);
}

+ (void)setConsoleLogOpen:(uint64_t)instance isOpen:(BOOL)isOpen {
    mars::xlog::SetConsoleLogOpen((uintptr_t)instance, isOpen ? true : false);
}

+ (void)setMaxFileSize:(uint64_t)instance maxFileSize:(long)maxFileSize {
    mars::xlog::SetMaxFileSize((uintptr_t)instance, maxFileSize);
}

+ (void)setMaxAliveTime:(uint64_t)instance aliveSeconds:(long)aliveSeconds {
    mars::xlog::SetMaxAliveTime((uintptr_t)instance, aliveSeconds);
}

+ (void)flush:(uint64_t)instance isSync:(BOOL)isSync {
    mars::xlog::Flush((uintptr_t)instance, isSync ? true : false);
}

+ (void)flushAll:(BOOL)isSync {
    mars::xlog::FlushAll(isSync ? true : false);
}

@end
