// Tencent is pleased to support the open source community by making Mars available.
// Copyright (C) 2016 THL A29 Limited, a Tencent company. All rights reserved.
//
// Licensed under the MIT License (the "License"); you may not use this file except in
// compliance with the License. You may obtain a copy of the License at
// http://opensource.org/licenses/MIT

#import <Foundation/Foundation.h>
#import "XLogConfig.h"
#import "XLogInstance.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Manages the lifecycle of xlog instances.
 *
 * All methods are class methods. Do not instantiate XLogManager.
 */
@interface XLogManager : NSObject

/**
 * Open (create or retrieve) a named xlog instance.
 *
 * Corresponds to xlog_new_instance(). If an instance with the same nameprefix
 * already exists, the existing instance is returned.
 *
 * @param config  Instance configuration. logdir and nameprefix must not be nil or empty.
 * @param level   Initial log level.
 * @return A valid XLogInstance, or nil if creation failed or config is invalid.
 */
+ (nullable XLogInstance *)openWithConfig:(XLogConfig *)config
                                    level:(XLogLevel)level;

/**
 * Retrieve an existing instance by name prefix.
 *
 * Corresponds to xlog_get_instance().
 *
 * @param nameprefix  The name prefix used when the instance was created.
 * @return The XLogInstance, or nil if not found.
 */
+ (nullable XLogInstance *)getInstanceByName:(NSString *)nameprefix;

/**
 * Check whether an instance with the given name prefix exists.
 *
 * Corresponds to xlog_has_instance().
 */
+ (BOOL)hasInstanceWithName:(NSString *)nameprefix;

/**
 * Release (close and destroy) an instance by name prefix.
 *
 * Corresponds to xlog_release_instance(). Uses delayed release internally
 * to avoid race conditions. After this call, any XLogInstance objects
 * referencing this name are invalidated.
 */
+ (void)releaseInstanceWithName:(NSString *)nameprefix;

/**
 * Destroy an instance by its XLogInstance object.
 *
 * Corresponds to xlog_destroy_instance(). Uses delayed release internally.
 * After this call, the XLogInstance object becomes invalid (isValid == NO).
 */
+ (void)destroyInstance:(XLogInstance *)instance;

/**
 * Flush all open log instances asynchronously.
 *
 * Corresponds to xlog_flush_all(). For synchronous flush of a specific instance,
 * use XLogInstance.flush: with YES.
 */
+ (void)flushAll;

@end

NS_ASSUME_NONNULL_END
