# xlog_flutter Darwin 原生封装设计文档

**日期：** 2026-03-25  
**状态：** 已批准  
**涉及平台：** iOS、macOS

---

## 1. 背景与目标

`xlog_flutter` 是一个基于 FFI 的 Flutter 插件，通过 Dart 层封装 mars xlog 的纯 C API（`xlog_capi.h`）。当前 iOS 和 macOS 的 `Classes/` 目录仅包含编译占位文件（`xlog_symbols.c`、`xlog_flutter.c`），没有面向原生开发者的 Objective-C 封装。

**目标：**
- 为 iOS 和 macOS 原生开发者提供完整的 Objective-C API，覆盖 `xlog_capi.h` 的全部功能
- iOS 和 macOS 共享同一套实现代码（`darwin/Classes/`）
- 封装代码随 Pod 分发，用户通过 `#import <xlog_flutter/XLog.h>` 引用
- 在 `example/ios` 和 `example/macos` 的 AppDelegate 中提供最小使用示例

---

## 2. 目录结构

```
samples/xlog_flutter/
├── darwin/
│   └── Classes/                        ← iOS 和 macOS 共享的 ObjC 封装源码
│       ├── XLog.h                      ← umbrella 导入头文件
│       ├── XLogConfig.h/.m             ← 对应 xlog_config_t
│       ├── XLogInstance.h/.m           ← 对应单个 xlog_handle_t
│       └── XLogManager.h/.m            ← 实例生命周期管理
├── ios/
│   ├── Classes/
│   │   ├── xlog_symbols.c              ← 保留（iOS 强制符号链接，不变）
│   │   └── (prepare_command 运行后复制来的 darwin/Classes/*)
│   └── xlog_flutter.podspec            ← 新增 prepare_command + 更新 source_files
├── macos/
│   ├── Classes/
│   │   ├── xlog_flutter.c              ← 保留（macOS 编译占位，不变）
│   │   └── (prepare_command 运行后复制来的 darwin/Classes/*)
│   └── xlog_flutter.podspec            ← 新增 prepare_command + 更新 source_files
└── example/
    ├── ios/
    │   └── Runner/
    │       └── AppDelegate.m           ← 新增：最小原生使用示例
    └── macos/
        └── Runner/
            └── AppDelegate.m           ← 新增：最小原生使用示例
```

---

## 3. ObjC API 设计

### 3.1 枚举类型

对应 `xlog_capi.h` 中的 C 枚举：

```objc
// 对应 xlog_level_t
typedef NS_ENUM(NSInteger, XLogLevel) {
    XLogLevelVerbose = 0,
    XLogLevelDebug   = 1,
    XLogLevelInfo    = 2,
    XLogLevelWarn    = 3,
    XLogLevelError   = 4,
    XLogLevelFatal   = 5,
    XLogLevelNone    = 6,
};

// 对应 xlog_appender_mode_t
typedef NS_ENUM(NSInteger, XLogAppenderMode) {
    XLogAppenderModeAsync = 0,
    XLogAppenderModeSync  = 1,
};

// 对应 xlog_compress_mode_t
typedef NS_ENUM(NSInteger, XLogCompressMode) {
    XLogCompressModeZlib = 0,
    XLogCompressModeZstd = 1,
};
```

### 3.2 XLogConfig

对应 `xlog_config_t`，封装日志实例的创建配置。

```objc
@interface XLogConfig : NSObject

/// 日志写入模式（默认 Async）
@property (nonatomic, assign) XLogAppenderMode mode;

/// 日志输出目录（必填）
@property (nonatomic, copy) NSString *logdir;

/// 实例标识前缀（必填，同时作为日志文件名前缀）
@property (nonatomic, copy) NSString *nameprefix;

/// 加密公钥（nil 表示不加密）
@property (nonatomic, copy, nullable) NSString *pubKey;

/// 压缩算法（默认 Zlib）
@property (nonatomic, assign) XLogCompressMode compressMode;

/// 压缩级别 0-9（默认 0）
@property (nonatomic, assign) int compressLevel;

/// 缓存目录（nil 表示禁用）
@property (nonatomic, copy, nullable) NSString *cachedir;

/// 缓存保留天数（0 表示不限）
@property (nonatomic, assign) int cacheDays;

@end
```

### 3.3 XLogInstance

封装单个 `xlog_handle_t`，提供日志写入和实例控制操作。

```objc
@interface XLogInstance : NSObject

/// 实例是否有效（handle 非空）
@property (nonatomic, readonly) BOOL isValid;

/// 当前日志级别（getter/setter 均支持）
@property (nonatomic, assign) XLogLevel level;

/// 当前写入模式
@property (nonatomic, assign) XLogAppenderMode appenderMode;

/// 是否同时输出到控制台
@property (nonatomic, assign) BOOL consoleLogOpen;

/// 当前日志文件路径（可能为 nil）
@property (nonatomic, readonly, nullable) NSString *logPath;

/// 各级别日志写入
- (void)verbose:(NSString *)tag msg:(NSString *)msg;
- (void)debug:(NSString *)tag msg:(NSString *)msg;
- (void)info:(NSString *)tag msg:(NSString *)msg;
- (void)warn:(NSString *)tag msg:(NSString *)msg;
- (void)error:(NSString *)tag msg:(NSString *)msg;
- (void)fatal:(NSString *)tag msg:(NSString *)msg;

/// 通用写入接口
- (void)write:(XLogLevel)level tag:(NSString *)tag msg:(NSString *)msg;

/// 查询指定级别是否启用
- (BOOL)isEnabledFor:(XLogLevel)level;

/// 刷新缓冲区（sync=YES 为同步 flush）
- (void)flush:(BOOL)sync;

@end
```

`XLogInstance` 不对外暴露初始化方法，只能通过 `XLogManager` 获取。

### 3.4 XLogManager

负责实例的完整生命周期管理，对应 `xlog_new_instance`、`xlog_get_instance`、`xlog_has_instance`、`xlog_release_instance`、`xlog_destroy_instance`、`xlog_flush_all`。

```objc
@interface XLogManager : NSObject

/// 创建或获取已有实例（对应 xlog_new_instance）
+ (nullable XLogInstance *)openWithConfig:(XLogConfig *)config
                                    level:(XLogLevel)level;

/// 获取已有实例（对应 xlog_get_instance，不存在返回 nil）
+ (nullable XLogInstance *)getInstanceByName:(NSString *)nameprefix;

/// 检查实例是否存在（对应 xlog_has_instance）
+ (BOOL)hasInstanceWithName:(NSString *)nameprefix;

/// 按名称释放实例（对应 xlog_release_instance）
+ (void)releaseInstanceWithName:(NSString *)nameprefix;

/// 销毁指定实例对象（对应 xlog_destroy_instance）
+ (void)destroyInstance:(XLogInstance *)instance;

/// 刷新所有实例（对应 xlog_flush_all）
+ (void)flushAll;

@end
```

### 3.5 XLog.h（umbrella header）

```objc
#import <xlog_flutter/XLogConfig.h>
#import <xlog_flutter/XLogInstance.h>
#import <xlog_flutter/XLogManager.h>
```

用户只需一行导入：
```objc
#import <xlog_flutter/XLog.h>
```

---

## 4. podspec 修改方案

### 4.1 iOS（`ios/xlog_flutter.podspec`）

新增 `prepare_command`，在 Pod 安装前将 `darwin/Classes/` 复制到 `ios/Classes/`：

```ruby
s.prepare_command = <<-CMD
  cp -r ../darwin/Classes/* Classes/ 2>/dev/null || true
CMD

s.source_files = 'Classes/**/*.{h,m,c}'
s.public_header_files = 'Classes/XLog.h',
                        'Classes/XLogConfig.h',
                        'Classes/XLogInstance.h',
                        'Classes/XLogManager.h'
```

**目录结构说明：** `ios/Classes/` 在 `prepare_command` 运行后包含：
- `xlog_symbols.c` — iOS 特有的符号强制链接文件（保留在 `ios/Classes/`，不复制）
- `XLog*.h/.m` — 从 `darwin/Classes/` 复制的共享代码
- `xlog_flutter.c` — 存根文件（若存在，也保留）

### 4.2 macOS（`macos/xlog_flutter.podspec`）

同样新增 `prepare_command`：

```ruby
s.prepare_command = <<-CMD
  cp -r ../darwin/Classes/* Classes/ 2>/dev/null || true
CMD

s.source_files = 'Classes/**/*.{h,m,c}'
s.public_header_files = 'Classes/XLog.h',
                        'Classes/XLogConfig.h',
                        'Classes/XLogInstance.h',
                        'Classes/XLogManager.h'
```

**目录结构说明：** `macos/Classes/` 在 `prepare_command` 运行后包含：
- `xlog_flutter.c` — macOS 编译占位文件（保留在 `macos/Classes/`，不覆盖）
- `XLog*.h/.m` — 从 `darwin/Classes/` 复制的共享代码

**本地开发工作流：** `prepare_command` 在使用 `:path` 本地引用时不会执行。

**推荐工作流：** 始终编辑 `darwin/Classes/` 下的源文件（作为唯一真实源），然后手动执行：
```bash
cp -r darwin/Classes/* ios/Classes/
cp -r darwin/Classes/* macos/Classes/
```

或在 CI/Pod 发布时由自动化脚本执行。这样保证源代码在 `darwin/` 中是单一权威。

---

## 5. 示例代码（AppDelegate）

iOS（`example/ios/Runner/AppDelegate.m`）和 macOS（`example/macos/Runner/AppDelegate.m`）在 `applicationDidFinishLaunching` 中添加：

```objc
#import <xlog_flutter/XLog.h>

// 1. 创建配置
XLogConfig *config = [[XLogConfig alloc] init];
config.logdir = [NSSearchPathForDirectoriesInDomains(
                    NSDocumentDirectory, NSUserDomainMask, YES).firstObject
                    stringByAppendingPathComponent:@"xlog"];
config.nameprefix   = @"demo";
config.mode         = XLogAppenderModeAsync;
config.compressMode = XLogCompressModeZlib;

// 2. 打开实例
XLogInstance *log = [XLogManager openWithConfig:config level:XLogLevelDebug];

// 3. 写日志
[log info:@"AppDelegate"  msg:@"xlog native wrapper initialized"];
[log debug:@"AppDelegate" msg:@"application did finish launching"];
[log warn:@"AppDelegate"  msg:@"this is a warning message"];

// 4. 关闭
[log flush:NO];
[XLogManager releaseInstanceWithName:@"demo"];
```

macOS 使用相同代码，仅 `logdir` 路径可替换为 `NSApplicationSupportDirectory`。

---

## 6. 实现注意事项

### 6.1 配置字段验证

`XLogManager.openWithConfig:level:` 实现需要：
1. 验证 `config.logdir` 和 `config.nameprefix` 均不为 `nil` 或空字符串，否则返回 `nil` 并记录错误
2. 捕获 `xlog_new_instance` 返回 0（失败）的情况，返回 `nil`
3. 根据需要发送 assertion 或日志

### 6.2 C API 字符串处理

`xlog_capi.h` 的函数参数均为 `const char *`，实现中需要注意：
- `NSString` → `const char *`：使用 `[str UTF8String]`，生命周期由 `NSString` 持有
- `xlog_get_log_path` 等返回 `const char *` 的函数：用 `[NSString stringWithUTF8String:]` 转换，允许返回 `nil`

### 6.3 xlog_write 参数映射

C API `xlog_write` 接受 `filename`、`funcname`、`line` 等源代码位置信息。ObjC 的便捷方法（`verbose:tag:msg:` 等）为了简化 API，不暴露这些参数，而是传递 `NULL`/空值。

如果用户需要指定源代码位置，可使用通用的 `write:tag:msg:` 方法并在 `msg` 中编码位置信息，或直接调用 C API。

### 6.4 xlog_level_t 完整性

C API 定义了 `XLOG_LEVEL_ALL = 0`（`XLOG_LEVEL_VERBOSE` 的别名），ObjC 枚举中故意省略 `XLogLevelAll`。开发者应使用 `XLogLevelVerbose`。

### 6.5 XLogInstance 内部 handle

`XLogInstance` 持有 `xlog_handle_t`（`void *`），不对外暴露。通过 `isValid` 属性判断是否有效，避免空指针调用。

### 6.6 iOS 与 macOS 的库加载差异

封装层本身（ObjC 代码）对两个平台完全一致，平台差异由各自 podspec 处理：
- iOS：静态 Framework（`xlog.framework`），符号通过 `xlog_symbols.c` 强制链接
- macOS：动态库（`libxlog.dylib`），运行时由 `@loader_path/Frameworks` 搜索加载

ObjC 封装层直接调用 C 函数，无需关心加载方式。

### 6.7 线程安全

ObjC 封装层不额外增加线程锁，线程安全由底层 C 库负责（xlog 本身是线程安全的）。

---

## 7. 文件清单

| 文件路径 | 类型 | 说明 |
|---|---|---|
| `darwin/Classes/XLog.h` | 新建 | umbrella 导入头 |
| `darwin/Classes/XLogConfig.h` | 新建 | 配置类头文件 |
| `darwin/Classes/XLogConfig.m` | 新建 | 配置类实现 |
| `darwin/Classes/XLogInstance.h` | 新建 | 实例类头文件 |
| `darwin/Classes/XLogInstance.m` | 新建 | 实例类实现 |
| `darwin/Classes/XLogManager.h` | 新建 | 管理器头文件 |
| `darwin/Classes/XLogManager.m` | 新建 | 管理器实现 |
| `ios/xlog_flutter.podspec` | 修改 | 新增 prepare_command、更新 source_files |
| `macos/xlog_flutter.podspec` | 修改 | 新增 prepare_command、更新 source_files |
| `example/ios/Runner/AppDelegate.m` | 修改 | 新增最小使用示例 |
| `example/macos/Runner/AppDelegate.m` | 修改 | 新增最小使用示例 |
