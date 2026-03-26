// Tencent is pleased to support the open source community by making Mars available.
// Copyright (C) 2016 THL A29 Limited, a Tencent company. All rights reserved.
//
// Licensed under the MIT License (the "License"); you may not use this file except in
// compliance with the License. You may obtain a copy of the License at
// http://opensource.org/licenses/MIT

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// MARK: - Enumerations

/// Log level. Corresponds to xlog_level_t in xlog_capi.h.
/// XLOG_LEVEL_ALL (= VERBOSE) is intentionally omitted; use XLogLevelVerbose instead.
typedef NS_ENUM(NSInteger, XLogLevel) {
    XLogLevelVerbose = 0,
    XLogLevelDebug   = 1,
    XLogLevelInfo    = 2,
    XLogLevelWarn    = 3,
    XLogLevelError   = 4,
    XLogLevelFatal   = 5,
    XLogLevelNone    = 6,
};

/// Appender mode. Corresponds to xlog_appender_mode_t in xlog_capi.h.
typedef NS_ENUM(NSInteger, XLogAppenderMode) {
    XLogAppenderModeAsync = 0,
    XLogAppenderModeSync  = 1,
};

/// Compression algorithm. Corresponds to xlog_compress_mode_t in xlog_capi.h.
typedef NS_ENUM(NSInteger, XLogCompressMode) {
    XLogCompressModeZlib = 0,
    XLogCompressModeZstd = 1,
};

// MARK: - XLogInstance

/**
 * Wraps a single xlog instance handle (xlog_handle_t / uintptr_t).
 *
 * Instances are obtained via XLogManager. Do not allocate directly.
 * All methods are no-ops when isValid is NO.
 */
@interface XLogInstance : NSObject

/// Whether the underlying handle is valid (non-zero).
@property (nonatomic, readonly) BOOL isValid;

/// Current log level (getter and setter).
@property (nonatomic, assign) XLogLevel level;

/// Current appender mode (async / sync). Setter only — C API has no getter.
@property (nonatomic, assign) XLogAppenderMode appenderMode;

/// Whether console log output is enabled. Setter only — C API has no getter.
@property (nonatomic, assign) BOOL consoleLogOpen;

/// Current log file path, or nil if unavailable.
@property (nonatomic, readonly, nullable) NSString *logPath;

// MARK: Convenience log methods

/// Write a VERBOSE level message.
- (void)verbose:(NSString *)tag msg:(NSString *)msg;

/// Write a DEBUG level message.
- (void)debug:(NSString *)tag msg:(NSString *)msg;

/// Write an INFO level message.
- (void)info:(NSString *)tag msg:(NSString *)msg;

/// Write a WARN level message.
- (void)warn:(NSString *)tag msg:(NSString *)msg;

/// Write an ERROR level message.
- (void)error:(NSString *)tag msg:(NSString *)msg;

/// Write a FATAL level message.
- (void)fatal:(NSString *)tag msg:(NSString *)msg;

/// Write a message at the specified level.
/// filename, funcname, and line are passed as NULL/0 for convenience.
- (void)write:(XLogLevel)level tag:(NSString *)tag msg:(NSString *)msg;

/// Check whether the specified level is currently enabled.
- (BOOL)isEnabledFor:(XLogLevel)level;

/// Flush the log buffer. Pass YES for synchronous flush.
- (void)flush:(BOOL)sync;

@end

// MARK: - Internal Category (for XLogManager use only)

/**
 * Internal methods used by XLogManager to access the private handle.
 * Do NOT call these from application code.
 */
@interface XLogInstance (Internal)
- (instancetype)initWithHandle:(uintptr_t)handle;
- (uintptr_t)_xlog_handle;
/// Zeroes the internal handle, marking this instance as invalid.
/// Called by XLogManager after destroying the native resource.
- (void)_invalidate;
@end

NS_ASSUME_NONNULL_END
