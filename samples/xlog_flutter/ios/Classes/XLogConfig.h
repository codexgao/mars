// Tencent is pleased to support the open source community by making Mars available.
// Copyright (C) 2016 THL A29 Limited, a Tencent company. All rights reserved.
//
// Licensed under the MIT License (the "License"); you may not use this file except in
// compliance with the License. You may obtain a copy of the License at
// http://opensource.org/licenses/MIT

#import <Foundation/Foundation.h>
#import "XLogInstance.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Configuration for opening an xlog instance.
 * Corresponds to xlog_config_t in xlog_capi.h.
 */
@interface XLogConfig : NSObject

/// Appender mode (default: XLogAppenderModeAsync).
@property (nonatomic, assign) XLogAppenderMode mode;

/// Log output directory path (required, must not be nil or empty).
@property (nonatomic, copy) NSString *logdir;

/// Instance name prefix used as identifier and log filename prefix
/// (required, must not be nil or empty).
@property (nonatomic, copy) NSString *nameprefix;

/// Encryption public key. nil means no encryption.
@property (nonatomic, copy, nullable) NSString *pubKey;

/// Compression algorithm (default: XLogCompressModeZlib).
@property (nonatomic, assign) XLogCompressMode compressMode;

/// Compression level 0-9 (default: 0).
@property (nonatomic, assign) int compressLevel;

/// Cache directory path. nil means caching is disabled.
@property (nonatomic, copy, nullable) NSString *cachedir;

/// Number of days to retain cached logs (0 = unlimited, default: 0).
@property (nonatomic, assign) int cacheDays;

@end

NS_ASSUME_NONNULL_END
