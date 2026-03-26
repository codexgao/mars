// Tencent is pleased to support the open source community by making Mars available.
// Copyright (C) 2016 THL A29 Limited, a Tencent company. All rights reserved.
//
// Licensed under the MIT License (the "License"); you may not use this file except in
// compliance with the License. You may obtain a copy of the License at
// http://opensource.org/licenses/MIT

#import "XLogInstance.h"
#include "xlog/xlog_capi.h"

@interface XLogInstance ()
@property (nonatomic, assign) uintptr_t handle;
// Backing storage for setter-only properties (C API has no getters)
@property (nonatomic, assign) XLogAppenderMode _appenderMode;
@property (nonatomic, assign) BOOL _consoleLogOpen;
@end

@implementation XLogInstance

// MARK: - Internal Category Implementation

- (instancetype)initWithHandle:(uintptr_t)handle {
    self = [super init];
    if (self) {
        _handle          = handle;
        __appenderMode   = XLogAppenderModeAsync;
        __consoleLogOpen = NO;
    }
    return self;
}

- (uintptr_t)_xlog_handle {
    return _handle;
}

- (void)_invalidate {
    _handle = 0;
}

// MARK: - Properties

- (BOOL)isValid {
    return _handle != 0;
}

- (XLogLevel)level {
    if (!self.isValid) return XLogLevelNone;
    return (XLogLevel)xlog_get_level(_handle);
}

- (void)setLevel:(XLogLevel)level {
    if (!self.isValid) return;
    xlog_set_level(_handle, (int)level);
}

- (XLogAppenderMode)appenderMode {
    return __appenderMode;
}

- (void)setAppenderMode:(XLogAppenderMode)appenderMode {
    __appenderMode = appenderMode;
    if (!self.isValid) return;
    xlog_set_appender_mode(_handle, (int)appenderMode);
}

- (BOOL)consoleLogOpen {
    return __consoleLogOpen;
}

- (void)setConsoleLogOpen:(BOOL)consoleLogOpen {
    __consoleLogOpen = consoleLogOpen;
    if (!self.isValid) return;
    xlog_set_console_log_open(_handle, consoleLogOpen ? 1 : 0);
}

- (nullable NSString *)logPath {
    if (!self.isValid) return nil;
    char buf[1024];
    int ok = xlog_get_log_path(_handle, buf, sizeof(buf));
    if (!ok || buf[0] == '\0') return nil;
    return [NSString stringWithUTF8String:buf];
}

// MARK: - Log writing

- (void)verbose:(NSString *)tag msg:(NSString *)msg {
    [self write:XLogLevelVerbose tag:tag msg:msg];
}

- (void)debug:(NSString *)tag msg:(NSString *)msg {
    [self write:XLogLevelDebug tag:tag msg:msg];
}

- (void)info:(NSString *)tag msg:(NSString *)msg {
    [self write:XLogLevelInfo tag:tag msg:msg];
}

- (void)warn:(NSString *)tag msg:(NSString *)msg {
    [self write:XLogLevelWarn tag:tag msg:msg];
}

- (void)error:(NSString *)tag msg:(NSString *)msg {
    [self write:XLogLevelError tag:tag msg:msg];
}

- (void)fatal:(NSString *)tag msg:(NSString *)msg {
    [self write:XLogLevelFatal tag:tag msg:msg];
}

- (void)write:(XLogLevel)level tag:(NSString *)tag msg:(NSString *)msg {
    if (!self.isValid) return;
    if (!msg) return;
    xlog_write(_handle,
               (int)level,
               tag ? [tag UTF8String] : "",
               NULL,   // filename: not exposed by convenience API
               NULL,   // funcname: not exposed by convenience API
               0,      // line: not exposed by convenience API
               [msg UTF8String]);
}

// MARK: - Control

- (BOOL)isEnabledFor:(XLogLevel)level {
    if (!self.isValid) return NO;
    return xlog_is_enabled_for(_handle, (int)level) != 0;
}

- (void)flush:(BOOL)sync {
    if (!self.isValid) return;
    xlog_flush(_handle, sync ? 1 : 0);
}

@end
