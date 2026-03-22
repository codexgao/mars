# xlog_flutter 平台规范化与断点调试支持 — 设计文档

**日期：** 2026-03-22  
**状态：** 待实现  
**范围：** iOS、macOS、Android、Windows（Linux 暂不涉及）

---

## 1. 背景与目标

### 问题

xlog_flutter 当前存在两个主要问题：

1. **非标准的 Debug/Release 库管理（iOS/macOS）**：podspec 在 `pod install` 时通过 Ruby 条件逻辑选择 Debug 或 Release XCFramework，导致：
   - 仓库同时存放两套库，浪费约 70MB 空间
   - 选择时机错误（`pod install` 时无法感知 Xcode build configuration）
   - 逻辑脆弱，依赖目录是否存在来决策

2. **无法断点调试 native 代码**：消费者项目接入 xlog_flutter 后，无法在 Xcode / Android Studio / Visual Studio 中对 MarsXlog native 代码设置断点。

### 目标

- iOS/macOS：遵循行业标准（Firebase、Sentry 等），只保留 Release 库，通过 XCFramework 内嵌 dSYM 支持符号调试
- Android：Debug build 使用含符号的未 strip `.so`，Release build 提供 stripped `.so` + 独立 `.so.sym` 文件
- Windows：Debug/Release 均提供 `.pdb`，随 Flutter build 输出自动分发给消费者

---

## 2. 整体架构

### 2.1 变更后的库文件布局

```
xlog_flutter/
├── ios/libs/
│   ├── Release/
│   │   └── MarsXlog.xcframework/          ← 仅保留 Release
│   │       ├── ios-arm64/
│   │       │   ├── MarsXlog.framework/
│   │       │   └── dSYMs/                 ← 新增：内嵌 dSYM
│   │       │       └── MarsXlog.framework.dSYM/
│   │       ├── ios-arm64_x86_64-simulator/
│   │       │   ├── MarsXlog.framework/
│   │       │   └── dSYMs/                 ← 新增：内嵌 dSYM
│   │       │       └── MarsXlog.framework.dSYM/
│   │       └── BCSymbolMaps/              ← 新增：bitcode 符号映射
│   └── Debug/                             ← 删除整个目录（节省 ~18MB）
│
├── macos/libs/
│   ├── Release/
│   │   └── MarsXlog.xcframework/          ← 仅保留 Release
│   │       ├── macos-arm64_x86_64/
│   │       │   ├── MarsXlog.framework/
│   │       │   └── dSYMs/                 ← 新增：内嵌 dSYM
│   │       │       └── MarsXlog.framework.dSYM/
│   │       └── BCSymbolMaps/              ← 新增（如适用）
│   └── Debug/                             ← 删除整个目录（节省 ~52MB）
│
├── android/libs/
│   ├── Debug/
│   │   └── {arch}/
│   │       └── libmarsxlog.so             ← 保留，不 strip（含 DWARF 符号）
│   └── Release/
│       └── {arch}/
│           ├── libmarsxlog.so             ← 已 strip（同现在）
│           └── libmarsxlog.so.sym         ← 新增：独立符号文件
│
└── windows/libs/x64/
    ├── Debug/
    │   ├── xlog.dll
    │   ├── xlog.lib
    │   └── xlog.pdb                       ← 新增
    └── Release/
        ├── xlog.dll
        ├── xlog.lib
        └── xlog.pdb                       ← 保持不变
```

### 2.2 节省空间

| 操作 | 节省 |
|------|------|
| 删除 `ios/libs/Debug/` | ~18MB |
| 删除 `macos/libs/Debug/` | ~52MB |
| **合计** | **~70MB** |

---

## 3. 平台详细设计

### 3.1 iOS / macOS — podspec 简化

#### 问题根源

CocoaPods 的 podspec 在 `pod install` 阶段由 Ruby 解析执行，此时 Xcode build configuration（Debug/Release）尚未确定。现有的条件判断逻辑本质上是一个无效的猜测，而非真正的构建时选择。

#### 变更

**`ios/xlog_flutter.podspec`**（macOS 同理）：

```ruby
# 删除（约 12 行）：
has_release = File.exist?(File.join(__dir__, 'libs/Release/MarsXlog.xcframework'))
has_debug   = File.exist?(File.join(__dir__, 'libs/Debug/MarsXlog.xcframework'))
if has_release || has_debug
  xcfw = has_debug ? 'libs/Debug/MarsXlog.xcframework' : 'libs/Release/MarsXlog.xcframework'
  s.vendored_frameworks = xcfw
end

# 替换为（1 行）：
s.vendored_frameworks = 'libs/Release/MarsXlog.xcframework'
```

#### dSYM 自动识别

CocoaPods 对 XCFramework 内嵌 dSYM 的处理遵循 Apple 规范：只要 dSYM 按如下结构放置在 XCFramework 内，Xcode 在 Debug 和 Archive 时会自动加载符号，**podspec 无需额外声明**。

```
MarsXlog.xcframework/
└── ios-arm64/
    ├── MarsXlog.framework/
    └── dSYMs/
        └── MarsXlog.framework.dSYM/
            └── Contents/
                ├── Info.plist
                └── Resources/DWARF/MarsXlog
```

#### 消费者断点调试体验

- Xcode Debug build：自动加载 dSYM，可在 MarsXlog C++ 代码中看到符号、调用栈
- Xcode Release/Archive：dSYM 随 XCFramework 打包，Instruments 和 Crash 报告均可符号化
- **限制**：无法单步执行 MarsXlog 内部逻辑（Release 库经过优化，源码行映射可能不精确）

#### 构建脚本要求

生成带 dSYM 的 XCFramework 需在构建命令中追加参数：

```bash
# iOS
python build_xlog_ios.py --xlog --config Release
# 构建脚本需确保 xcodebuild 使用 DEBUG_INFORMATION_FORMAT=dwarf-with-dsym
# 并在 xcodebuild -create-xcframework 时包含 -debug-symbols 参数

# macOS
python build_xlog_mac.py --xlog --config Release
# 同上
```

生成的 dSYM 目录需手动或通过脚本放入 XCFramework 对应 slice 的 `dSYMs/` 子目录。

---

### 3.2 Android — 分层符号支持

#### 现状

`android/CMakeLists.txt` 已正确按 `CMAKE_BUILD_TYPE` 选择 Debug/Release 库，无需修改库选择逻辑。需补充：Release build 关联独立符号文件。

#### `android/CMakeLists.txt` 变更

在现有 `add_library(marsxlog SHARED IMPORTED)` 之后新增：

```cmake
# 新增：Release build 时关联独立符号文件（供 LLDB 加载）
if(NOT CMAKE_BUILD_TYPE STREQUAL "Debug")
  set(XLOG_SYM "${LIB_DIR}/${ANDROID_ABI}/libmarsxlog.so.sym")
  if(EXISTS "${XLOG_SYM}")
    set_target_properties(marsxlog PROPERTIES
      IMPORTED_LOCATION_DEBUG "${XLOG_SYM}"
    )
  endif()
endif()
```

#### Debug vs Release 对比

| | Debug `libmarsxlog.so` | Release `libmarsxlog.so` |
|--|------------------------|--------------------------|
| 符号表 | 保留（不 strip，含 DWARF） | 已 strip |
| 文件大小 | 较大 | 较小 |
| 断点调试 | Android Studio 直接识别，可单步执行 | 需配合 `.so.sym` 查看调用栈 |
| 构建参数 | `-g -O0` | `-O2 -g` 编译，`llvm-strip` 后保留 `.sym` |

#### 生成 `.so.sym` 的方式

```bash
# 使用 NDK 提供的 llvm-objcopy 从未 strip 的 .so 提取符号
$NDK/toolchains/llvm/prebuilt/*/bin/llvm-objcopy \
  --only-keep-debug \
  libmarsxlog.so \
  libmarsxlog.so.sym
```

此操作由 Android 构建脚本（`build_android.py`）负责，输出文件放入 `android/libs/Release/{arch}/`。

#### 消费者断点调试体验

- **Debug build**：Android Studio 自动识别未 strip 的 `libmarsxlog.so`，可直接在 MarsXlog C++ 代码中设断点、单步执行
- **Release build**：在 Android Studio LLDB 控制台执行 `add-dsym <path>/libmarsxlog.so.sym` 后可查看符号化调用栈

---

### 3.3 Windows — 统一 .pdb 分发

#### 现状

`windows/CMakeLists.txt` 已使用 CMake generator expression 正确处理 Debug/Release 库选择。仅缺：
1. `windows/libs/x64/Debug/xlog.pdb` 文件（构建脚本未生成）
2. CMakeLists 未将 `.pdb` 加入 `bundled_libraries`

#### `windows/CMakeLists.txt` 变更

```cmake
# 新增：pdb 路径（Debug/Release 统一处理）
set(XLOG_PDB
  "$<$<CONFIG:Debug>:${LIB_DIR}/x64/Debug/xlog.pdb>$<$<NOT:$<CONFIG:Debug>>:${LIB_DIR}/x64/Release/xlog.pdb>")

# 修改 bundled_libraries，追加 pdb
set(xlog_flutter_bundled_libraries
  $<TARGET_FILE:xlog_flutter>
  "${XLOG_DLL}"
  "${XLOG_PDB}"          # 新增
  PARENT_SCOPE
)
```

#### 消费者断点调试体验

`.pdb` 随 Flutter build 输出目录（`build/windows/runner/`）一起分发，Visual Studio 和 WinDbg 会自动发现同目录下的 `.pdb` 文件，无需消费者手动配置。

#### 构建脚本要求

`build_windows.py` 在 Debug 构建时需确保生成 `.pdb`：

```
windows/libs/x64/Debug/xlog.pdb    ← 需新增，由 build_windows.py --config Debug 生成
windows/libs/x64/Release/xlog.pdb  ← 已存在，保持不变
```

---

## 4. 需改动的文件清单

| 文件 | 变更类型 | 描述 |
|------|----------|------|
| `ios/xlog_flutter.podspec` | 修改 | 删除条件逻辑，固定引用 `libs/Release/MarsXlog.xcframework` |
| `macos/xlog_flutter.podspec` | 修改 | 同上 |
| `android/CMakeLists.txt` | 修改 | 新增 Release build 关联 `.so.sym` |
| `windows/CMakeLists.txt` | 修改 | 新增 `XLOG_PDB` 变量，追加至 `bundled_libraries` |
| `ios/libs/Debug/` | 删除 | 整个目录（~18MB） |
| `macos/libs/Debug/` | 删除 | 整个目录（~52MB） |
| `ios/libs/Release/MarsXlog.xcframework` | 重建 | 内嵌 dSYM（构建脚本更新后重新生成） |
| `macos/libs/Release/MarsXlog.xcframework` | 重建 | 内嵌 dSYM（同上） |
| `android/libs/Release/{arch}/libmarsxlog.so.sym` | 新增 | 独立符号文件（构建脚本生成） |
| `windows/libs/x64/Debug/xlog.pdb` | 新增 | Debug pdb（构建脚本生成） |
| `CODEBUDDY.md` | 修改 | 更新预编译库路径说明，补充符号文件说明 |

---

## 5. 不在本次范围内

- **Linux**：无测试环境，暂不实现
- **iOS/macOS Debug 单步调试**：CocoaPods 架构限制，Release-only + dSYM 是行业标准做法
- **Android x86/x86_64 支持**：独立需求，不在本次范围

---

## 6. 参考

- [Apple: Distributing Binary Frameworks as Swift Packages](https://developer.apple.com/documentation/xcode/distributing-binary-frameworks-as-swift-packages)
- [CocoaPods: vendored_frameworks](https://guides.cocoapods.org/syntax/podspec.html#vendored_frameworks)
- [Android NDK: Add native debug symbols](https://developer.android.com/studio/build/shrink-code#native-crash-support)
- [CMake: bundled_libraries for Flutter plugins](https://docs.flutter.dev/platform-integration/desktop/building#cmake-windows)
