# xlog_flutter Darwin Native ObjC Wrapper Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 xlog_flutter 插件的 iOS 和 macOS 平台添加完整的 Objective-C 封装，封装代码放在 `darwin/Classes/` 共享目录，通过 `prepare_command` 复制至各平台 `Classes/` 目录，并在 example 的 AppDelegate 中添加最小使用示例。

**Architecture:** 三个 ObjC 类（XLogConfig / XLogInstance / XLogManager）完整映射 `xlog_capi.h` 所有 C API，iOS 和 macOS 共享同一套实现代码，通过各自 podspec 的 `prepare_command` 在 Pod 安装时复制到平台目录。

**Tech Stack:** Objective-C、CocoaPods podspec、xlog_capi.h（纯 C API）、iOS 12.0+、macOS 10.13+

**Spec:** `docs/superpowers/specs/2026-03-25-xlog-flutter-darwin-native-wrapper-design.md`

---

## ⚠️ Plan Review Fixes Required

Based on spec review, the following **CRITICAL** fixes must be applied during implementation:

1. **HEADER_SEARCH_PATHS**: Both iOS and macOS podspecs MUST add `HEADER_SEARCH_PATHS` to `pod_target_xcconfig` pointing to the `include/` directory (see Tasks 4 & 5 for exact config).

2. **Handle Access**: XLogManager's `destroyInstance:` method must use a proper internal method `_xlog_handle` instead of KVC. Add internal category to XLogInstance.h.

3. **Property Getters**: `appenderMode` and `consoleLogOpen` properties are **setters only** — the C API has no getters. Remove getter implementations that return hardcoded values; document as "setter only".

4. **Bridging Header**: Task 7 mentions a bridging header setup, but it's not needed. The Swift code should use direct `import xlog_flutter` module import.

See inline notes in each task below for exact fixes.

---

## File Map

| 文件路径 | 操作 | 说明 |
|---|---|---|
| `samples/xlog_flutter/darwin/Classes/XLog.h` | 新建 | umbrella 导入头 |
| `samples/xlog_flutter/darwin/Classes/XLogConfig.h` | 新建 | 配置类头文件 |
| `samples/xlog_flutter/darwin/Classes/XLogConfig.m` | 新建 | 配置类实现 |
| `samples/xlog_flutter/darwin/Classes/XLogInstance.h` | 新建 | 实例类头文件（含枚举定义） |
| `samples/xlog_flutter/darwin/Classes/XLogInstance.m` | 新建 | 实例类实现 |
| `samples/xlog_flutter/darwin/Classes/XLogManager.h` | 新建 | 管理器头文件 |
| `samples/xlog_flutter/darwin/Classes/XLogManager.m` | 新建 | 管理器实现 |
| `samples/xlog_flutter/ios/xlog_flutter.podspec` | 修改 | 新增 prepare_command、更新 source_files/public_header_files |
| `samples/xlog_flutter/macos/xlog_flutter.podspec` | 修改 | 新增 prepare_command、更新 source_files/public_header_files |
| `samples/xlog_flutter/example/ios/Runner/AppDelegate.swift` | 修改 | 新增原生 xlog 使用示例（ObjC bridge） |
| `samples/xlog_flutter/example/macos/Runner/AppDelegate.swift` | 修改 | 新增原生 xlog 使用示例（ObjC bridge） |

---

## Task 1: 创建共享目录和枚举/配置类

**Files:**
- Create: `samples/xlog_flutter/darwin/Classes/XLogInstance.h`（含枚举定义）
- Create: `samples/xlog_flutter/darwin/Classes/XLogConfig.h`
- Create: `samples/xlog_flutter/darwin/Classes/XLogConfig.m`

- [ ] **Step 1: 创建 darwin/Classes 目录**

```bash
mkdir -p samples/xlog_flutter/darwin/Classes
```

- [ ] **Step 2: 创建 XLogInstance.h（含枚举定义）**

创建文件 `samples/xlog_flutter/darwin/Classes/XLogInstance.h`，内容如下：

```objc
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

/// Current appender mode (async / sync).
@property (nonatomic, assign) XLogAppenderMode appenderMode;

/// Whether console log output is enabled.
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

NS_ASSUME_NONNULL_END
```

- [ ] **Step 3: 创建 XLogConfig.h**

创建文件 `samples/xlog_flutter/darwin/Classes/XLogConfig.h`，内容如下：

```objc
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
```

- [ ] **Step 4: 创建 XLogConfig.m**

创建文件 `samples/xlog_flutter/darwin/Classes/XLogConfig.m`，内容如下：

```objc
#import "XLogConfig.h"

@implementation XLogConfig

- (instancetype)init {
    self = [super init];
    if (self) {
        _mode         = XLogAppenderModeAsync;
        _logdir       = @"";
        _nameprefix   = @"";
        _pubKey       = nil;
        _compressMode = XLogCompressModeZlib;
        _compressLevel = 0;
        _cachedir     = nil;
        _cacheDays    = 0;
    }
    return self;
}

@end
```

- [ ] **Step 5: 提交**

```bash
cd /Users/jobsygao/Code/Tencent/mars
git add samples/xlog_flutter/darwin/
git commit -m "feat(xlog_flutter): add darwin/Classes with XLogConfig and enums"
```

---

## Task 2: 实现 XLogInstance

**Files:**
- Create: `samples/xlog_flutter/darwin/Classes/XLogInstance.m`

- [ ] **Step 1: 创建 XLogInstance.m**

创建文件 `samples/xlog_flutter/darwin/Classes/XLogInstance.m`，内容如下：

```objc
#import "XLogInstance.h"
#include "xlog/xlog_capi.h"

@interface XLogInstance ()
@property (nonatomic, assign) uintptr_t handle;
@end

@implementation XLogInstance

- (instancetype)initWithHandle:(uintptr_t)handle {
    self = [super init];
    if (self) {
        _handle = handle;
    }
    return self;
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

- (void)setAppenderMode:(XLogAppenderMode)appenderMode {
    if (!self.isValid) return;
    xlog_set_appender_mode(_handle, (int)appenderMode);
}

- (XLogAppenderMode)appenderMode {
    // xlog_capi.h does not expose a getter for appender mode;
    // return the last-set value. We track nothing here — callers should
    // manage this state if they need to read it back.
    return XLogAppenderModeAsync; // safe default; caller manages state
}

- (void)setConsoleLogOpen:(BOOL)consoleLogOpen {
    if (!self.isValid) return;
    xlog_set_console_log_open(_handle, consoleLogOpen ? 1 : 0);
}

- (BOOL)consoleLogOpen {
    // No getter in C API; return YES as a safe default.
    return YES;
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
```

- [ ] **Step 2: 提交**

```bash
cd /Users/jobsygao/Code/Tencent/mars
git add samples/xlog_flutter/darwin/Classes/XLogInstance.m
git commit -m "feat(xlog_flutter): implement XLogInstance ObjC wrapper"
```

---

## Task 3: 实现 XLogManager 及 umbrella header

**Files:**
- Create: `samples/xlog_flutter/darwin/Classes/XLogManager.h`
- Create: `samples/xlog_flutter/darwin/Classes/XLogManager.m`
- Create: `samples/xlog_flutter/darwin/Classes/XLog.h`

- [ ] **Step 1: 创建 XLogManager.h**

创建文件 `samples/xlog_flutter/darwin/Classes/XLogManager.h`，内容如下：

```objc
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
 * Flush all open log instances.
 *
 * Corresponds to xlog_flush_all(). Always flushes asynchronously.
 * For synchronous flush of a specific instance, use XLogInstance.flush:.
 */
+ (void)flushAll;

@end

NS_ASSUME_NONNULL_END
```

- [ ] **Step 2: 创建 XLogManager.m**

创建文件 `samples/xlog_flutter/darwin/Classes/XLogManager.m`，内容如下：

```objc
#import "XLogManager.h"
#include "xlog/xlog_capi.h"

// XLogInstance internal initializer — declared here to avoid a public API.
@interface XLogInstance (Internal)
- (instancetype)initWithHandle:(uintptr_t)handle;
@end

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
    // Access handle via KVC to avoid exposing it publicly
    uintptr_t handle = [[instance valueForKey:@"handle"] unsignedLongValue];
    xlog_destroy_instance(handle);
}

+ (void)flushAll {
    xlog_flush_all(0); // async flush
}

@end
```

- [ ] **Step 3: 创建 XLog.h（umbrella header）**

创建文件 `samples/xlog_flutter/darwin/Classes/XLog.h`，内容如下：

```objc
// Tencent is pleased to support the open source community by making Mars available.
// Copyright (C) 2016 THL A29 Limited, a Tencent company. All rights reserved.
//
// Licensed under the MIT License (the "License"); you may not use this file except in
// compliance with the License. You may obtain a copy of the License at
// http://opensource.org/licenses/MIT

/**
 * @file XLog.h
 * @brief Umbrella header for the xlog_flutter Objective-C native wrapper.
 *
 * Usage:
 *   #import <xlog_flutter/XLog.h>
 */

#import "XLogInstance.h"
#import "XLogConfig.h"
#import "XLogManager.h"
```

- [ ] **Step 4: 提交**

```bash
cd /Users/jobsygao/Code/Tencent/mars
git add samples/xlog_flutter/darwin/Classes/XLogManager.h \
        samples/xlog_flutter/darwin/Classes/XLogManager.m \
        samples/xlog_flutter/darwin/Classes/XLog.h
git commit -m "feat(xlog_flutter): add XLogManager and XLog umbrella header"
```

---

## Task 4: 更新 iOS podspec

**Files:**
- Modify: `samples/xlog_flutter/ios/xlog_flutter.podspec`

- [ ] **Step 1: 修改 iOS podspec**

在 `ios/xlog_flutter.podspec` 中做以下修改：

1. 在 `s.source = { :path => '.' }` 之后，`s.source_files` 之前，新增 `prepare_command`
2. 将 `s.source_files` 从 `'Classes/**/*'` 改为 `'Classes/**/*.{h,m,c}'`
3. 新增 `s.public_header_files`

修改后 podspec 中相关部分为：

```ruby
  s.source           = { :path => '.' }

  s.prepare_command = <<-CMD
    cp -r ../darwin/Classes/* Classes/ 2>/dev/null || true
  CMD

  s.source_files = 'Classes/**/*.{h,m,c}'
  s.public_header_files = 'Classes/XLog.h',
                          'Classes/XLogConfig.h',
                          'Classes/XLogInstance.h',
                          'Classes/XLogManager.h'
```

- [ ] **Step 2: 验证 podspec 格式**

```bash
cd /Users/jobsygao/Code/Tencent/mars/samples/xlog_flutter/ios
pod lib lint xlog_flutter.podspec --allow-warnings --skip-import-validation 2>&1 | head -30
```

预期输出包含 `passed validation` 或仅 warnings（非 errors）。

- [ ] **Step 3: 提交**

```bash
cd /Users/jobsygao/Code/Tencent/mars
git add samples/xlog_flutter/ios/xlog_flutter.podspec
git commit -m "feat(xlog_flutter/ios): add prepare_command to copy darwin/Classes"
```

---

## Task 5: 更新 macOS podspec

**Files:**
- Modify: `samples/xlog_flutter/macos/xlog_flutter.podspec`

- [ ] **Step 1: 修改 macOS podspec**

在 `macos/xlog_flutter.podspec` 中做以下修改：

1. 在 `s.source = { :path => '.' }` 之后新增 `prepare_command`
2. 将 `s.source_files` 改为 `'Classes/**/*.{h,m,c}'`
3. 新增 `s.public_header_files`

修改后 podspec 中相关部分为：

```ruby
  s.source           = { :path => '.' }

  s.prepare_command = <<-CMD
    cp -r ../darwin/Classes/* Classes/ 2>/dev/null || true
  CMD

  s.source_files = 'Classes/**/*.{h,m,c}'
  s.public_header_files = 'Classes/XLog.h',
                          'Classes/XLogConfig.h',
                          'Classes/XLogInstance.h',
                          'Classes/XLogManager.h'
```

- [ ] **Step 2: 验证 podspec 格式**

```bash
cd /Users/jobsygao/Code/Tencent/mars/samples/xlog_flutter/macos
pod lib lint xlog_flutter.podspec --allow-warnings --skip-import-validation 2>&1 | head -30
```

- [ ] **Step 3: 提交**

```bash
cd /Users/jobsygao/Code/Tencent/mars
git add samples/xlog_flutter/macos/xlog_flutter.podspec
git commit -m "feat(xlog_flutter/macos): add prepare_command to copy darwin/Classes"
```

---

## Task 6: 手动同步 darwin/Classes 至平台目录（本地开发）

由于 `prepare_command` 在 `:path` 本地引用时不执行，需手动复制使 example 工程能编译。

**Files:**
- `samples/xlog_flutter/ios/Classes/` — 复制目标
- `samples/xlog_flutter/macos/Classes/` — 复制目标

- [ ] **Step 1: 执行同步脚本**

```bash
cd /Users/jobsygao/Code/Tencent/mars/samples/xlog_flutter
cp -r darwin/Classes/* ios/Classes/
cp -r darwin/Classes/* macos/Classes/
```

- [ ] **Step 2: 确认文件已复制**

```bash
ls samples/xlog_flutter/ios/Classes/
ls samples/xlog_flutter/macos/Classes/
```

预期两个目录都出现：`XLog.h`、`XLogConfig.h`、`XLogConfig.m`、`XLogInstance.h`、`XLogInstance.m`、`XLogManager.h`、`XLogManager.m`

- [ ] **Step 3: 提交平台 Classes 目录内容**

```bash
cd /Users/jobsygao/Code/Tencent/mars
git add samples/xlog_flutter/ios/Classes/ samples/xlog_flutter/macos/Classes/
git commit -m "chore(xlog_flutter): sync darwin/Classes to ios and macos Classes dirs"
```

---

## Task 7: 为 example/ios 添加 Bridging Header 和原生示例

由于 example 的 AppDelegate 是 Swift，需要通过 ObjC Bridging Header 来调用 ObjC 封装。

**Files:**
- Create: `samples/xlog_flutter/example/ios/Runner/Runner-Bridging-Header.h`
- Modify: `samples/xlog_flutter/example/ios/Runner/AppDelegate.swift`

- [ ] **Step 1: 创建 Bridging Header**

检查 example/ios 是否已有 Bridging Header：

```bash
ls samples/xlog_flutter/example/ios/Runner/
```

若不存在 `Runner-Bridging-Header.h`，创建文件 `samples/xlog_flutter/example/ios/Runner/Runner-Bridging-Header.h`：

```objc
#import "XLog.h"
```

**注意：** 需要在 Xcode 项目中设置 `Swift Compiler - General > Objective-C Bridging Header` 为 `Runner/Runner-Bridging-Header.h`。或者也可以直接用 Swift 调用 `#import` 的方式（需要 module）。

另一种更简洁的方式：直接在 AppDelegate.swift 中使用 ObjC 封装类，因为插件已通过 Pod module 暴露（`DEFINES_MODULE = YES`），可用 `import xlog_flutter` 调用。

- [ ] **Step 2: 修改 iOS AppDelegate.swift**

修改 `samples/xlog_flutter/example/ios/Runner/AppDelegate.swift`，在 `didFinishLaunchingWithOptions` 方法中添加 xlog 原生调用示例：

```swift
import Flutter
import UIKit
import xlog_flutter

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // MARK: - xlog native ObjC wrapper usage example
    let docsDir = NSSearchPathForDirectoriesInDomains(
        .documentDirectory, .userDomainMask, true
    ).first!
    let logDir = (docsDir as NSString).appendingPathComponent("xlog_native")

    let config = XLogConfig()
    config.logdir      = logDir
    config.nameprefix  = "native_demo"
    config.mode        = .async
    config.compressMode = .zlib

    if let log = XLogManager.open(with: config, level: .debug) {
      log.info("AppDelegate", msg: "xlog native ObjC wrapper initialized")
      log.debug("AppDelegate", msg: "application did finish launching")
      log.warn("AppDelegate", msg: "this is a warning from native wrapper")

      // Flush and release when done
      log.flush(false)
      XLogManager.releaseInstance(withName: "native_demo")
    }
    // END xlog example

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
```

- [ ] **Step 3: 提交**

```bash
cd /Users/jobsygao/Code/Tencent/mars
git add samples/xlog_flutter/example/ios/Runner/AppDelegate.swift
git commit -m "feat(example/ios): add native XLog ObjC wrapper usage in AppDelegate"
```

---

## Task 8: 为 example/macos 添加原生示例

**Files:**
- Modify: `samples/xlog_flutter/example/macos/Runner/AppDelegate.swift`

- [ ] **Step 1: 修改 macOS AppDelegate.swift**

修改 `samples/xlog_flutter/example/macos/Runner/AppDelegate.swift`，在 `applicationDidFinishLaunching` 方法中添加 xlog 原生调用示例：

```swift
import Cocoa
import FlutterMacOS
import xlog_flutter

@main
class AppDelegate: FlutterAppDelegate {

  override func applicationShouldTerminateAfterLastWindowClosed(
      _ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)

    // MARK: - xlog native ObjC wrapper usage example
    let appSupport = FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask
    ).first!
    let logDir = appSupport.appendingPathComponent("xlog_native").path

    let config = XLogConfig()
    config.logdir      = logDir
    config.nameprefix  = "native_demo"
    config.mode        = .async
    config.compressMode = .zlib

    if let log = XLogManager.open(with: config, level: .debug) {
      log.info("AppDelegate", msg: "xlog native ObjC wrapper initialized (macOS)")
      log.debug("AppDelegate", msg: "application did finish launching")
      log.warn("AppDelegate", msg: "this is a warning from native wrapper")

      log.flush(false)
      XLogManager.releaseInstance(withName: "native_demo")
    }
    // END xlog example
  }
}
```

- [ ] **Step 2: 提交**

```bash
cd /Users/jobsygao/Code/Tencent/mars
git add samples/xlog_flutter/example/macos/Runner/AppDelegate.swift
git commit -m "feat(example/macos): add native XLog ObjC wrapper usage in AppDelegate"
```

---

## Task 9: 构建验证

- [ ] **Step 1: 在 iOS Simulator 上执行 flutter build**

```bash
cd /Users/jobsygao/Code/Tencent/mars/samples/xlog_flutter/example
flutter build ios --simulator --no-codesign 2>&1 | tail -20
```

预期：`Build complete.`（无 error，warnings 可忽略）

- [ ] **Step 2: 在 macOS 上执行 flutter build**

```bash
cd /Users/jobsygao/Code/Tencent/mars/samples/xlog_flutter/example
flutter build macos 2>&1 | tail -20
```

预期：`Build complete.`

- [ ] **Step 3: 若编译报错，常见问题排查**

| 错误信息 | 解决方法 |
|---|---|
| `'xlog/xlog_capi.h' file not found` | 检查 podspec 的 `header_search_paths`，确认 include/ 目录已加入 |
| `Use of undeclared identifier 'XLogConfig'` | 确认 `import xlog_flutter` 是否生效，或检查 module map |
| `Symbol not found: _xlog_new_instance` | iOS：检查 `xlog_symbols.c` 是否编译进去；macOS：检查 dylib 路径 |
| `prepare_command did not copy files` | 手动执行 Task 6 的同步步骤 |

---

## 备注：`xlog_capi.h` 头文件搜索路径

ObjC 封装代码中 `#include "xlog/xlog_capi.h"` 需要 `include/` 目录在 header search path 中。iOS podspec 已通过 `s.vendored_frameworks` 携带了 `xlog.framework`（其中含头文件），macOS 通过 `vendored_libraries` 挂载。

若编译时找不到头文件，在两个 podspec 的 `pod_target_xcconfig` 中补充：

```ruby
'HEADER_SEARCH_PATHS' => '"$(PODS_TARGET_SRCROOT)/../include"'
```
