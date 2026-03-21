# CODEBUDDY.md

This file provides guidance to CodeBuddy Code when working with code in this repository.

## Project Overview

Mars 是腾讯微信团队开发的跨平台基础设施组件，已被数十亿微信用户验证。支持 iOS、macOS、Android、Windows 等平台。

**核心组件：**
- **comm**: 通用库，包含 socket、线程、消息队列、协程等工具
- **xlog**: 高性能可靠的日志组件
- **sdt**: 网络检测/诊断组件
- **stn**: 信令网络组件（核心网络层）
- **app**: 应用层抽象
- **baseevent**: 前后台、网络变化事件处理
- **boot**: 组件初始化和生命周期管理

## 构建要求

**Python 版本：** 3.10 或以上（所有构建脚本必需）

**平台特定工具链：**
- **Android**: NDK r20+、Gradle
- **iOS/macOS**: Xcode、CMake
- **Windows**: Visual Studio 2022（或 VS 2019）、CMake
- **通用**: CMake 3.6+

## 构建命令

### Android

```bash
cd mars

# 构建原生库（使用 Python 脚本）
python build_android.py

# 或使用 Gradle
./gradlew build

# 增量构建
python build_android.py --incremental True

# 指定架构 (armeabi-v7a, arm64-v8a, x86, x86_64)
python build_android.py --arch arm64-v8a
```

**输出位置：** `libraries/mars_android_sdk/libs/` 和 `libraries/mars_xlog_sdk/libs/`

### iOS

```bash
cd mars

# 构建 iOS 库（生成 mars.framework）
python build_ios.py

# 仅构建 Xlog
python build_ios.py --xlog

# 生成 Xcode 项目
python build_ios.py --gen_project
```

**输出位置：** `cmake_build/iOS/iOS.out/mars.framework`

### macOS

```bash
cd mars

# 构建 macOS 库
python build_osx.py

# 仅构建 Xlog
python build_osx.py --xlog
```

**输出位置：** `cmake_build/OSX/OSX.out/mars.framework`

### watchOS

```bash
cd mars
python build_watch.py
```

### Windows

**环境变量（必须设置）：**
```bash
set MSVC_BIN_HOST64_PATH="C:/Program Files (x86)/Microsoft Visual Studio/2019/Professional/VC/Tools/MSVC/14.29.30133/bin/Hostx64/"
set MSVC_TOOLS_PATH="C:/Program Files (x86)/Microsoft Visual Studio/2019/Professional/Common7/Tools"
```

**构建命令：**
```bash
cd mars

# 完整 Mars 库（Release）
python build_windows.py --mars --config Release

# 完整 Mars 库（Debug）
python build_windows.py --mars --config Debug

# 仅 Xlog
python build_windows.py --xlog --config Release

# 生成 Visual Studio 项目
python build_windows.py --gen_project

# 增量构建
python build_windows.py --mars --config Release --incremental True
```

**输出位置：** `cmake_build/Windows/Windows.out/win/`
- `mars.lib` - 合并后的静态库
- PDB 文件（用于调试）

### 跨平台 CMake

```bash
cd mars
mkdir cmake_build && cd cmake_build
cmake ..
cmake --build . --target install
```

## 代码组织结构

```
mars/
├── comm/                    # 通用库 (224 个文件)
│   ├── socket/             # Socket 操作
│   ├── thread/             # 线程工具
│   ├── coroutine/          # 协程支持
│   ├── crypt/              # 加密工具
│   ├── dns/                # DNS 解析
│   ├── debugger/           # 测试/调试工具
│   └── CMakeLists.txt
├── xlog/                    # 日志组件 (33 个文件)
│   ├── src/                # 日志实现
│   ├── crypt/              # 日志加密
│   ├── jni/                # Android JNI 绑定
│   ├── objc/               # iOS Objective-C 绑定
│   ├── appender.h          # 日志输出器接口
│   └── CMakeLists.txt
├── stn/                     # 信令网络 (98 个文件)
│   ├── src/                # STN 实现
│   ├── jni/                # Android JNI 绑定
│   ├── proto/              # Protocol Buffer 定义
│   ├── test_cases/         # 测试套件
│   ├── stn_logic.*         # 主要 STN 逻辑
│   └── CMakeLists.txt
├── sdt/                     # 网络检测 (40 个文件)
│   ├── src/                # 诊断实现
│   ├── sdt_logic.*         # 检测逻辑
│   └── CMakeLists.txt
├── app/                     # 应用层回调
├── baseevent/              # 事件处理（前后台、网络变化）
├── boot/                   # 组件初始化
├── openssl/                # OpenSSL 库
├── boost/                  # Boost 工具库头文件
├── zstd/                   # 压缩库
├── googletest/             # Google Test 框架
├── googlemock/             # Google Mock 框架
├── CMakeLists.txt          # 根 CMakeLists
└── build_*.py              # 平台特定构建脚本
```

## 代码风格指南

**缩进：** 4 个空格（不使用制表符）

**私有函数：** 以 `__`（双下划线）开头
```cpp
void __private_function() { }
```

**函数参数：** 以 `_`（单下划线）开头
```cpp
void process(int _value, const string& _name) { }
```

**风格标准：** 遵循 [Google C++ 风格指南](http://zh-google-styleguide.readthedocs.io/en/latest/google-cpp-styleguide/)

## 核心架构概念

### 任务模型

网络请求建模为 `Task` 对象，包含：
- `taskid`: 任务唯一标识
- `cmdid`: 命令 ID
- `cgi`: 请求路径
- `channel_select`: 通道选择

回调流程：`Req2Buf`（序列化） → 网络传输 → `Buf2Resp`（反序列化） → `OnTaskEnd`（完成处理）

### 长链路 vs 短链路

- **长链路（Long Link）**: 持久 TCP/QUIC 连接，用于实时信令、推送消息、低延迟请求
- **短链路（Short Link）**: 传统 HTTP/HTTPS，用于一次性请求、上传、下载
- **通道选择**: 通过 `channel_select` 指定（`kChannelShort`、`kChannelLong`、`kChannelBoth`）

### 初始化顺序（关键）

1. `SetCallback()` - 先注册所有回调
2. `Mars.init()` / `mars::baseevent::OnCreate()` - 初始化 Mars 平台
3. 配置：`SetClientVersion()`、`SetLonglinkSvrAddr()`、`SetShortlinkSvrAddr()`
4. `OnForeground(true)` - 设置初始前台状态（默认为后台）
5. `MakesureLonglinkConnected()` - 触发连接

**清理步骤：**
```cpp
Mars.onDestroy()  // 销毁 Mars
appender_close()  // 关闭 xlog
```

### 多进程安全

- Xlog 支持多进程日志，**每个进程必须使用单独的日志目录**
- 永远不要在进程间共享日志目录

### 事件驱动设计

baseevent 层处理：
- 前后台切换：`OnForeground()`
- 网络变化：`OnNetworkChange()`
- 账号变化：需要调用 `StnLogic::reset()`

## Android 集成

### 库加载

```java
System.loadLibrary("c++_shared");
System.loadLibrary("marsxlog");
System.loadLibrary("marsstn");
```

### Xlog 初始化

```java
// 使用独占文件夹存储日志（SIGBUS 问题预防）
String cachePath = this.getFilesDir() + "/xlog";

Xlog xlog = new Xlog();
Log.setLogImp(xlog);

if (BuildConfig.DEBUG) {
    Log.setConsoleLogOpen(true);
    Log.appenderOpen(Xlog.LEVEL_DEBUG, Xlog.AppenderModeAsync, 
        "", logPath, logFileName, 0);
} else {
    Log.setConsoleLogOpen(false);
    Log.appenderOpen(Xlog.LEVEL_INFO, Xlog.AppenderModeAsync, 
        "", logPath, logFileName, 0);
}
```

### STN 初始化

```java
// 设置回调
AppLogic.setCallBack(stub);
StnLogic.setCallBack(stub);
SdtLogic.setCallBack(stub);

// 初始化 Mars
Mars.init(getApplicationContext(), new Handler(Looper.getMainLooper()));

// 配置服务器地址
StnLogic.setLonglinkSvrAddr(profile.longLinkHost(), profile.longLinkPorts());
StnLogic.setShortlinkSvrAddr(profile.shortLinkPort());
StnLogic.setClientVersion(profile.productID());

// 启动 Mars
Mars.onCreate(true);
BaseEvent.onForeground(true);
StnLogic.makesureLongLinkConnected();
```

### Gradle 依赖

```gradle
dependencies {
    implementation 'com.tencent.mars:mars-core:1.2.5'      // 完整 Mars
    // 或
    implementation 'com.tencent.mars:mars-xlog:1.2.5'      // 仅 Xlog
    // 或
    implementation 'com.tencent.mars:mars-wrapper:1.2.5'  // 包装器（快速演示）
}
```

## iOS/macOS 集成

### Framework 使用

1. 将生成的 `mars.framework` 添加到 Xcode 项目
2. 在 Build Phases 中链接 framework
3. 在 Build Settings 中配置头文件搜索路径

### 关键注意事项

- 通过 `setxattr` 禁用日志目录备份：`com.apple.MobileBackup`
- 使用包装类将 C++ 回调桥接到 Objective-C

## Windows 集成

### 环境配置

确保链接 OpenSSL 库：
- `openssl/openssl_lib_windows/x86/libcrypto.lib`
- `openssl/openssl_lib_windows/x86/libssl.lib`

或 x64 版本：
- `openssl/openssl_lib_windows/x64/libcrypto.lib`
- `openssl/openssl_lib_windows/x64/libssl.lib`

### Visual Studio 项目生成

```bash
cd mars
python build_windows.py --gen_project
# 打开 cmake_build/Windows/mars.sln
```

## 文件扩展名说明

**.rewriteme 文件**

这些是模板文件，集成时需要：
1. 删除 `.rewriteme` 扩展名
2. 将文件重命名为对应的 `.cc` 文件
3. 这些文件包含平台特定的回调实现

## 分支和贡献工作流

### 分支说明

- **master**: 发布分支（标签: 1.1.0, 1.2.0, ...）**不要在此分支提交 PR**
- **develop**: 活跃开发分支 **在此分支提交功能/修复 PR**
- **hotfix**: 紧急修复分支（仅用于生产版本的紧急问题）

### PR 提交流程

1. Fork 仓库并从 `master` 或 `hotfix` 创建分支
2. 更新代码或 API 文档（如有更改）
3. 为新文件添加版权声明
4. 检查代码 lint 和风格
5. 充分测试代码
6. 提交 PR 到 `develop` 或 `hotfix` 分支

## 测试

### 测试框架

- Google Test（googletest）- 包含在代码库中
- Google Mock（googlemock）- 包含在代码库中

### 测试文件位置

- `/mars/comm/debugger/test_spy_sample.cc` - 调试器/间谍测试
- `/mars/stn/test_cases/test_constants.h` - STN 测试常量
- `/mars/stn/test_support_mock/` - 测试模拟支持

### 运行测试

通过 CMake 构建测试目标或使用平台特定的测试运行器。

## 示例项目

示例代码位于 `samples/` 目录：

- `samples/android/xlogSample` - Xlog 演示
- `samples/android/marsSampleChat` - 完整 Mars 网络演示
- `samples/iOS/iOSDemo` - iOS 完整集成
- `samples/Mac/` - macOS 演示
- `samples/Windows/` - Windows 演示
- `samples/xlog_flutter/` - Flutter 插件集成

## 常见开发任务

### 添加新网络请求（Task）

1. 定义 Task：创建包含 `taskid`、`cmdid`、`cgi` 路径、`channel_select` 的 Task
2. 实现 `Req2Buf`：将请求数据序列化为 `AutoBuffer`
3. 实现 `Buf2Resp`：从 `AutoBuffer` 反序列化响应，返回错误码
4. 实现 `OnTaskEnd`：处理完成（成功/失败/超时）
5. 提交 Task：通过 STN API 调用 `StartTask(task)`

### 调试网络问题

- 启用 xlog 控制台输出：`appender_set_console_log(true)` 和 `xlogger_SetLevel(kLevelDebug)`
- 检查配置日志目录中的 xlog 文件
- 监视回调：`ReportConnectStatus`、`OnLongLinkNetworkError`、`OnShortLinkNetworkError`
- 使用 SDT 组件进行网络诊断

### 修改加密/打包

- 长链路编码器：实现自定义 `LongLinkEncoder` 接口，通过 `LonglinkConfig` 注册
- 短链路：在 `Req2Buf`/`Buf2Resp` 回调中自定义
- Xlog 加密：在 `XLogConfig` 中提供 `pub_key` 以实现公钥加密

## 代码风格检查

使用 clang-format 进行代码格式化。排除的目录在 `clang_format_ignore.txt` 中定义（第三方库、示例、构建输出）。

## 重要安全提示

- 不要提交包含敏感数据的日志文件
- 为 xlog 使用专用目录（文件可能自动删除）
- 避免在代码中存储凭证 - 使用安全存储机制
- Xlog 支持通过公钥配置进行加密
- 多进程场景中，每个进程必须使用独立的日志目录
