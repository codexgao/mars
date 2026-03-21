# MarsXlog.xcframework 大小优化建议

## 当前大小分析

**总大小：18MB**

| 组件 | 大小 |
|------|------|
| `ios-arm64/MarsXlog.framework/MarsXlog` | 8.8MB |
| `ios-x86_64-simulator/MarsXlog.framework/MarsXlog` | 9.1MB |
| 头文件及元数据 | ~1MB |

两个静态库（静态 ar archive）分别对应真机（arm64）和模拟器（x86_64），打包在同一个 xcframework 中。

---

## 优化方案

### 方案一：移除调试符号 + 启用 LTO

**预期节省：30–45%（约 5–8MB）**，难度低，优先推荐。

在构建 MarsXlog 的 CMakeLists.txt 中添加：

```cmake
# Release 构建标志：开启优化、隐藏内部符号
set(CMAKE_CXX_FLAGS_RELEASE
    "-O3 -DNDEBUG -fvisibility=hidden -fvisibility-inlines-hidden")

# 开启链接时优化（LTO）
set(CMAKE_INTERPROCEDURAL_OPTIMIZATION TRUE)

# 移除无用代码段（Dead Code Stripping）
set(CMAKE_CXX_FLAGS_RELEASE
    "${CMAKE_CXX_FLAGS_RELEASE} -ffunction-sections -fdata-sections")
set(CMAKE_SHARED_LINKER_FLAGS
    "${CMAKE_SHARED_LINKER_FLAGS} -Wl,-dead_strip")
```

同时确认 Xcode Build Settings（若通过 Xcode 构建）：
- `DEAD_CODE_STRIPPING` = YES
- `DEBUG_INFORMATION_FORMAT` = `dwarf-with-dsym`（Release 下不内嵌调试符号）
- `STRIP_INSTALLED_PRODUCT` = YES

---

### 方案二：分离设备与模拟器的发布包

**可节省：约 9MB（50%）**，适用于生产环境。

当前 xcframework 同时包含真机和模拟器二进制，开发阶段需要模拟器，但线上发布包只需要 arm64。可按以下策略拆分：

- **生产发布**：仅打包 `ios-arm64`（约 8.8MB）
- **开发调试**：保留完整 xcframework（含 `ios-x86_64-simulator`）

podspec 可通过环境变量区分：

```ruby
# xlog_flutter.podspec
if ENV['XLOG_SIMULATOR_ONLY']
  s.vendored_frameworks = 'libs/Release/MarsXlog-simulator.xcframework'
else
  s.vendored_frameworks = 'libs/Release/MarsXlog.xcframework'
end
```

构建时分别生成：
```bash
# 仅真机（用于发布）
xcodebuild archive -scheme MarsXlog -destination "generic/platform=iOS"

# 仅模拟器（用于开发）
xcodebuild archive -scheme MarsXlog -destination "generic/platform=iOS Simulator"

# 合并为完整 xcframework（用于开发包）
xcodebuild -create-xcframework \
  -framework path/to/device/MarsXlog.framework \
  -framework path/to/simulator/MarsXlog.framework \
  -output MarsXlog.xcframework
```

---

### 方案三：精简头文件

**预期节省：100–150KB**，收益较小，可选执行。

当前 xcframework 内嵌了 `comm/` 和 `xlog/` 共 17 个头文件。其中 `xlog_flutter.cpp` 实际只依赖：

- `xlog/appender.h`
- `xlog/xlogger_interface.h`
- `xlog/xloggerbase.h`

可在构建时只将必要的头文件打包进 framework，移除 `comm/` 下未使用的辅助头文件。

---

## 优先级汇总

| 优先级 | 方案 | 预期节省 | 实施难度 |
|--------|------|--------|--------|
| 1 | 移除调试符号 + 启用 LTO + Dead Code Strip | 30–45% | 低 |
| 2 | 分离设备/模拟器发布包 | ~50% | 中 |
| 3 | 精简内嵌头文件 | <1% | 低 |

综合实施方案一和方案二后，生产环境发布包预期可从 **18MB 降至 5–9MB**。
