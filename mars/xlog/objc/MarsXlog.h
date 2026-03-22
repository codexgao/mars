// Tencent is pleased to support the open source community by making Mars available.
// Copyright (C) 2016 THL A29 Limited, a Tencent company. All rights reserved.

// Licensed under the MIT License (the "License"); you may not use this file except in
// compliance with the License. You may obtain a copy of the License at
// http://opensource.org/licenses/MIT

// Unless required by applicable law or agreed to in writing, software distributed under the License is
// distributed on an "AS IS" basis, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
// either express or implied. See the License for the specific language governing permissions and
// limitations under the License.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, MarsXLogLevel) {
    MarsXLogLevelVerbose = 0,
    MarsXLogLevelDebug,
    MarsXLogLevelInfo,
    MarsXLogLevelWarn,
    MarsXLogLevelError,
    MarsXLogLevelFatal,
    MarsXLogLevelNone
};

typedef NS_ENUM(NSInteger, MarsXLogAppenderMode) {
    MarsXLogAppenderModeAsync = 0,
    MarsXLogAppenderModeSync = 1
};

typedef NS_ENUM(NSInteger, MarsXLogCompressMode) {
    MarsXLogCompressModeZlib = 0,
    MarsXLogCompressModeZstd = 1
};

@interface MarsXLogConfig : NSObject
@property (nonatomic, assign) MarsXLogLevel level;
@property (nonatomic, assign) MarsXLogAppenderMode mode;
@property (nonatomic, copy) NSString *logdir;
@property (nonatomic, copy) NSString *nameprefix;
@property (nonatomic, copy) NSString *pubkey;
@property (nonatomic, assign) MarsXLogCompressMode compressmode;
@property (nonatomic, assign) NSInteger compresslevel;
@property (nonatomic, copy, nullable) NSString *cachedir;
@property (nonatomic, assign) NSInteger cachedays;
@end

@interface MarsXlog : NSObject

+ (uint64_t)newXloggerInstanceWithConfig:(MarsXLogConfig *)config;
+ (uint64_t)getXloggerInstanceWithNameprefix:(NSString *)nameprefix;
+ (void)releaseXloggerInstanceWithNameprefix:(NSString *)nameprefix;
+ (void)destroyXlogInstance:(uint64_t)instance;
+ (BOOL)hasXlogInstance:(NSString *)nameprefix;
+ (NSArray<NSString *> *)getAllXlogInstanceNames;

+ (void)logWrite:(uint64_t)instance
           level:(MarsXLogLevel)level
             tag:(NSString *)tag
             log:(NSString *)log;

+ (MarsXLogLevel)getLogLevel:(uint64_t)instance;
+ (void)setLogLevel:(uint64_t)instance level:(MarsXLogLevel)level;
+ (void)setAppenderMode:(uint64_t)instance mode:(MarsXLogAppenderMode)mode;
+ (void)setConsoleLogOpen:(uint64_t)instance isOpen:(BOOL)isOpen;
+ (void)setMaxFileSize:(uint64_t)instance maxFileSize:(long)maxFileSize;
+ (void)setMaxAliveTime:(uint64_t)instance aliveSeconds:(long)aliveSeconds;

+ (void)flush:(uint64_t)instance isSync:(BOOL)isSync;
+ (void)flushAll:(BOOL)isSync;

@end

NS_ASSUME_NONNULL_END
