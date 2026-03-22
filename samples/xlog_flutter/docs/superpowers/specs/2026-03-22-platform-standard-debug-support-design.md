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

#### dSYM 分发策略

| Slice | 包含 dSYM | 理由 |
|-------|---------|------|
| `ios-arm64` | ✅ 是 | 物理设备调试与崩溃符号化必需 |
| `ios-arm64_x86_64-simulator` | ✅ 是 | 完整的调试体验，易于开发者测试 |

#### 消费者断点调试体验

- Xcode Debug build：自动加载 dSYM，可在 MarsXlog C++ 代码中看到符号、调用栈
- Xcode Release/Archive：dSYM 随 XCFramework 打包，Instruments 和 Crash 报告均可符号化
- **限制**：无法单步执行 MarsXlog 内部逻辑（Release 库经过优化，源码行映射可能不精确）

#### dSYM 生成与校验

在构建脚本（`build_xlog_ios.py`）中需要确保：

1. **构建时启用符号生成**：
```bash
xcodebuild build \
  -scheme MarsXlog_arm64 \
  -configuration Release \
  DEBUG_INFORMATION_FORMAT=dwarf-with-dsym
```

2. **提取 dSYM 并放入 XCFramework**：
```bash
# 从构建输出找到 dSYM
dsym_src="cmake_build/iOS/build/Release/arm64/MarsXlog.framework.dSYM"

# 目标路径（在 XCFramework 内）
dsym_dst="ios/libs/Release/MarsXlog.xcframework/ios-arm64/dSYMs"

# 复制
mkdir -p "$dsym_dst"
cp -r "$dsym_src" "$dsym_dst/MarsXlog.framework.dSYM"
```

3. **校验 DWARF 有效性**（构建脚本校验或手工验证）：
```bash
xcrun dwarfdump -v \
  ios/libs/Release/MarsXlog.xcframework/ios-arm64/dSYMs/MarsXlog.framework.dSYM/Contents/Resources/DWARF/MarsXlog | head -20
# 应输出：DW_OP_* 操作码，说明 DWARF 数据有效
```

4. **验证 CocoaPods 处理**：完成 `pod install` 后检查：
```bash
ls -la Pods/xlog_flutter/ios/libs/Release/MarsXlog.xcframework/ios-arm64/dSYMs/
# 应列出: MarsXlog.framework.dSYM/
```

---

### 3.2 Android — 分层符号支持

#### 现状

`android/CMakeLists.txt` 已正确按 `CMAKE_BUILD_TYPE` 选择 Debug/Release 库，**无需修改 CMakeLists 构建链**。仅需调整预编译库的构建方式。

#### `android/CMakeLists.txt` 无需改动

当前实现已正确：
```cmake
if(CMAKE_BUILD_TYPE STREQUAL "Debug")
  set(LIB_DIR "${PLUGIN_ANDROID_REAL}/libs/Debug")
else()
  set(LIB_DIR "${PLUGIN_ANDROID_REAL}/libs/Release")
endif()

add_library(marsxlog SHARED IMPORTED)
set_target_properties(marsxlog PROPERTIES
  IMPORTED_LOCATION "${XLOG_SO}"
)
target_link_libraries(xlog_flutter PRIVATE marsxlog log z)
```

保持此逻辑**不变**。符号支持通过预编译库的构建方式实现，而非 CMake 配置。

#### Debug vs Release 对比

| | Debug `libmarsxlog.so` | Release `libmarsxlog.so` |
|--|------------------------|--------------------------|
| 符号表 | 保留（不 strip，含 DWARF） | 已 strip（通过 `llvm-strip --strip-all`） |
| 独立符号文件 | 无 | `libmarsxlog.so.sym` |
| 文件大小 | 较大（含完整调试信息） | 较小 |
| 断点调试 | Android Studio 直接识别，可单步执行 MarsXlog 内部逻辑 | 需手动加载 `.so.sym` 查看调用栈 |

#### 生成 `.so.sym` 的方式（构建脚本负责）

```bash
# 在 build_android.py 中，Release build 完成后执行：

# 1. 先从完整的 .so 提取符号信息
$NDK/toolchains/llvm/prebuilt/*/bin/llvm-objcopy \
  --only-keep-debug \
  libmarsxlog.so \
  libmarsxlog.so.sym

# 2. 然后 strip 原始 .so（替换）
$NDK/toolchains/llvm/prebuilt/*/bin/llvm-strip \
  --strip-all \
  libmarsxlog.so

# 3. 输出文件放入仓库
cp libmarsxlog.so.sym android/libs/Release/{arch}/libmarsxlog.so.sym
```

此操作由 Android 构建脚本（`build_android.py`）负责，构建完成后将生成的 `.so.sym` 提交到仓库。

#### 消费者断点调试体验

- **Debug build**：Android Studio 自动识别未 strip 的 `libmarsxlog.so`，可直接在 MarsXlog C++ 代码中设断点、单步执行
- **Release build**：
  - 方法 1（推荐）：在 Android Studio Debugger Symbols 配置中手动添加 `.so.sym` 路径
  - 方法 2：项目的 `build.gradle.kts` 中配置将 `.so.sym` 复制到 `/data/local/tmp/` 供 LLDB 加载

#### 具体方法（Release 下加载 .so.sym）

```kotlin
// app/build.gradle.kts 示例
tasks.register("copySymbolsForDebug") {
  dependsOn("externalNativeBuild${buildVariant.name.capitalize()}")
  doLast {
    val nativeLibDir = "${project.buildDir}/intermediates/cmake/release/obj"
    val arch = "arm64-v8a"  // 或其他目标架构
    val symbolFile = "${rootProject.projectDir}/xlog_flutter/android/libs/Release/$arch/libmarsxlog.so.sym"
    val destDir = File("/data/local/tmp")
    
    if (file(symbolFile).exists()) {
      file(symbolFile).copyTo(File(destDir, "libmarsxlog.so.sym"), overwrite = true)
      println("Symbol file copied: $symbolFile -> ${destDir.absolutePath}")
    }
  }
}
```

然后在 Android Studio 中：
1. Run → Edit Configurations
2. Debugger → Debug symbols directories
3. 添加 `/data/local/tmp` 或本地 `.so.sym` 所在路径

---

### 3.3 Windows — 统一 .pdb 分发

#### 现状

`windows/CMakeLists.txt` 已使用 CMake generator expression 正确处理 Debug/Release 库选择。仅缺：
1. `windows/libs/x64/Debug/xlog.pdb` 文件（构建脚本未生成）
2. CMakeLists 未将 `.pdb` 加入 `bundled_libraries`

#### `windows/CMakeLists.txt` 变更

```cmake
# 新增：pdb 路径定义（使用 CMake $<IF:> 生成器表达式）
set(XLOG_PDB
  "$<IF:$<CONFIG:Debug>,${LIB_DIR}/x64/Debug/xlog.pdb,${LIB_DIR}/x64/Release/xlog.pdb>")

# 修改 bundled_libraries，追加 pdb
set(xlog_flutter_bundled_libraries
  $<TARGET_FILE:xlog_flutter>
  "${XLOG_DLL}"
  "${XLOG_PDB}"          # 新增
  PARENT_SCOPE
)
```

**关键点**：使用 `$<IF:...>` 而非嵌套的 `$<NOT:>` 来避免 CMake 语法错误。

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
| `windows/CMakeLists.txt` | 修改 | 新增 `XLOG_PDB` 变量，追加至 `bundled_libraries` |
| `ios/libs/Debug/` | 删除 | 整个目录（~18MB） |
| `macos/libs/Debug/` | 删除 | 整个目录（~52MB） |
| `ios/libs/Release/MarsXlog.xcframework` | 重建 | 内嵌 dSYM（构建脚本更新后重新生成） |
| `macos/libs/Release/MarsXlog.xcframework` | 重建 | 内嵌 dSYM（构建脚本更新后重新生成） |
| `android/libs/Release/{arch}/libmarsxlog.so.sym` | 新增 | 独立符号文件（构建脚本生成） |
| `windows/libs/x64/Debug/xlog.pdb` | 新增 | Debug pdb（构建脚本生成） |
| `CODEBUDDY.md` | 修改 | 更新预编译库路径说明，补充符号文件说明 |
| `build_xlog_ios.py`（if exists）| 修改 | 更新为生成带 dSYM 的 XCFramework |
| `build_xlog_mac.py`（if exists）| 修改 | 更新为生成带 dSYM 的 XCFramework |
| `build_android.py`（if exists）| 修改 | Release build 时生成 `.so.sym` 文件 |
| `build_windows.py`（if exists）| 修改 | Debug build 时生成 `.pdb` 文件 |

---

## 5. 不在本次范围内

- **Linux**：无测试环境，暂不实现
- **iOS/macOS Debug 单步调试**：CocoaPods 架构限制使得在 `pod install` 时无法动态选择库。Release-only + dSYM 内嵌是 Firebase、Sentry 等主流方案的标准做法。若要真正支持 Debug 单步调试，需要消费者在 Podfile 中手动引入 Debug XCFramework，这增加接入成本且易出错
- **Android x86/x86_64 支持**：独立需求，可后续实现

---

## 6. 实现检查清单

### 阶段 1：podspec 和 CMakeLists 改动（无需重建库）

- [ ] 修改 `ios/xlog_flutter.podspec`：删除条件逻辑，固定引用 Release
- [ ] 修改 `macos/xlog_flutter.podspec`：同上
- [ ] 修改 `windows/CMakeLists.txt`：新增 `XLOG_PDB` 变量和 bundled_libraries
- [ ] 验证 CMake 语法（使用 `cmake --check-system-vars`）
- [ ] 更新 `CODEBUDDY.md` 中的文件路径说明和符号调试说明
- [ ] 提交这些文件改动到 git

### 阶段 2：预编译库的重建和提交（需访问构建系统）

**iOS：**
- [ ] 更新 `build_xlog_ios.py` 脚本以生成带 dSYM 的 XCFramework
- [ ] 删除 `ios/libs/Debug/` 目录
- [ ] 执行 `python build_xlog_ios.py --xlog --config Release`
- [ ] 验证 dSYM 结构：`ls -la ios/libs/Release/MarsXlog.xcframework/ios-arm64/dSYMs/`
- [ ] 验证 DWARF 数据：`xcrun dwarfdump -v ios/libs/Release/MarsXlog.xcframework/ios-arm64/dSYMs/MarsXlog.framework.dSYM/Contents/Resources/DWARF/MarsXlog | head -20`

**macOS：**
- [ ] 更新 `build_xlog_mac.py` 脚本以生成带 dSYM 的 XCFramework
- [ ] 删除 `macos/libs/Debug/` 目录
- [ ] 执行 `python build_xlog_mac.py --xlog --config Release`
- [ ] 验证 dSYM 结构：`ls -la macos/libs/Release/MarsXlog.xcframework/macos-arm64_x86_64/dSYMs/`

**Android：**
- [ ] 更新 `build_android.py` 脚本，Release 构建完成后执行 `llvm-objcopy --only-keep-debug` 生成 `.so.sym`
- [ ] 执行 `python build_android.py --config Release`
- [ ] 验证：`ls -la android/libs/Release/arm64-v8a/libmarsxlog.so.sym`
- [ ] 确保 Debug 构建的 `.so` 未被 strip：`nm android/libs/Debug/arm64-v8a/libmarsxlog.so | head`（应输出符号表）

**Windows：**
- [ ] 更新 `build_windows.py` 脚本确保 Debug 构建生成 `.pdb`
- [ ] 执行 `python build_windows.py --xlog --config Debug`
- [ ] 验证：`ls -la windows/libs/x64/Debug/xlog.pdb`

### 阶段 3：验收

- [ ] 在 iOS 示例项目中 `pod install` 后检查 dSYM：`find Pods/xlog_flutter -name "*.dSYM" -type d`
- [ ] 在 macOS 示例项目中同上
- [ ] Android Debug build 在 Android Studio 中设置 native breakpoint 并测试
- [ ] Android Release build 配置 LLDB 符号路径，检查调用栈
- [ ] Windows Debug build 在 Visual Studio 中设置 breakpoint 并测试
- [ ] 提交所有库文件改动

---

## 7. 参考

- [Apple: Distributing Binary Frameworks as Swift Packages](https://developer.apple.com/documentation/xcode/distributing-binary-frameworks-as-swift-packages)
- [CocoaPods: vendored_frameworks](https://guides.cocoapods.org/syntax/podspec.html#vendored_frameworks)
- [Android NDK: Add native debug symbols](https://developer.android.com/studio/build/shrink-code#native-crash-support)
- [CMake: bundled_libraries for Flutter plugins](https://docs.flutter.dev/platform-integration/desktop/building#cmake-windows)
