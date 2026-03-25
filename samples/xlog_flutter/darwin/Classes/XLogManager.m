// Tencent is pleased to support the open source community by making Mars available.
// Copyright (C) 2016 THL A29 Limited, a Tencent company. All rights reserved.
//
// Licensed under the MIT License (the "License"); you may not use this file except in
// compliance with the License. You may obtain a copy of the License at
// http://opensource.org/licenses/MIT

#import "XLogManager.h"
#include "xlog/xlog_capi.h"

@implementation XLogManager

+ (nullable XLogInstance *)openWithConfig:(XLogConfig *)config
                                    level:(XLogLevel)level {
    // Validate required fields
    if (!config) {
        NSLog(@"[XLogManager] openWithConfig: config must not be nil");
        return nil;
    }
    if (config.logdir.length == 0) {
        NSLog(@"[XLogManager] openWithConfig: config.logdir must not be empty");
        return nil;
    }
    if (config.nameprefix.length == 0) {
        NSLog(@"[XLogManager] openWithConfig: config.nameprefix must not be empty");
        return nil;
    }

    xlog_config_t c_config;
    c_config.mode           = (xlog_appender_mode_t)config.mode;
    c_config.logdir         = [config.logdir UTF8String];
    c_config.nameprefix     = [config.nameprefix UTF8String];
    c_config.pub_key        = config.pubKey ? [config.pubKey UTF8String] : NULL;
    c_config.compress_mode  = (xlog_compress_mode_t)config.compressMode;
    c_config.compress_level = config.compressLevel;
    c_config.cachedir       = config.cachedir ? [config.cachedir UTF8String] : NULL;
    c_config.cache_days     = config.cacheDays;

    uintptr_t handle = xlog_new_instance(&c_config, (xlog_level_t)level);
    if (handle == 0) {
        NSLog(@"[XLogManager] openWithConfig: xlog_new_instance failed for prefix '%@'",
              config.nameprefix);
        return nil;
    }

    return [[XLogInstance alloc] initWithHandle:handle];
}

+ (nullable XLogInstance *)getInstanceByName:(NSString *)nameprefix {
    if (nameprefix.length == 0) return nil;
    uintptr_t handle = xlog_get_instance([nameprefix UTF8String]);
    if (handle == 0) return nil;
    return [[XLogInstance alloc] initWithHandle:handle];
}

+ (BOOL)hasInstanceWithName:(NSString *)nameprefix {
    if (nameprefix.length == 0) return NO;
    return xlog_has_instance([nameprefix UTF8String]) != 0;
}

+ (void)releaseInstanceWithName:(NSString *)nameprefix {
    if (nameprefix.length == 0) return;
    xlog_release_instance([nameprefix UTF8String]);
}

+ (void)destroyInstance:(XLogInstance *)instance {
    if (!instance || !instance.isValid) return;
    xlog_destroy_instance([instance _xlog_handle]);
}

+ (void)flushAll {
    xlog_flush_all(0); // async flush
}

@end
