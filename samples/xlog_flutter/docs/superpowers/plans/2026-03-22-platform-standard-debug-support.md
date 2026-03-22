# Platform Standard Practices & Debug Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 xlog_flutter 插件在 iOS/macOS/Android/Windows 各平台遵循行业标准做法，并通过调试符号支持消费者项目的 native 断点调试。

**Architecture:** 分两个阶段。阶段一：修改 podspec 和 CMakeLists 等配置文件（不需要重建库，可立即提交）。阶段二：更新构建脚本以生成调试符号（dSYM/sym/pdb），重建库并提交。

**Tech Stack:** CocoaPods (Ruby podspec), CMake, Python (build scripts), XCFramework, Android NDK (llvm-objcopy/llvm-strip), MSVC/PDB

**Spec:** `docs/superpowers/specs/2026-03-22-platform-standard-debug-support-design.md`

---

## 文件变更地图

### 阶段一（配置文件，立即可改）

| 文件 | 操作 | 说明 |
|------|------|------|
| `ios/xlog_flutter.podspec` | 修改 | 删除 Ruby 条件逻辑，固定引用 Release |
| `macos/xlog_flutter.podspec` | 修改 | 同上 |
| `windows/CMakeLists.txt` | 修改 | 新增 XLOG_PDB 变量，追加至 bundled_libraries |
| `CODEBUDDY.md` | 修改 | 更新文档，补充符号调试说明 |

### 阶段二（构建脚本 + 重建库）

| 文件 | 操作 | 说明 |
|------|------|------|
| `mars/build_xlog_ios.py` | 修改 | 添加 embed_dsyms() 函数，在 xcframework 生成后自动内嵌 dSYM |
| `mars/build_xlog_mac.py` | 修改 | 同上（macOS 版本） |
| `mars/build_android.py` | 修改 | Release 构建后自动生成 .so.sym |
| `mars/build_windows.py` 或 `mars/build_xlog_windows.py` | 修改 | Debug 构建时确保生成 .pdb |
| `ios/libs/Debug/` | 删除 | 整个目录（~18MB） |
| `macos/libs/Debug/` | 删除 | 整个目录（~52MB） |
| `ios/libs/Release/MarsXlog.xcframework` | 重建 | 内嵌 dSYM 后重新提交 |
| `macos/libs/Release/MarsXlog.xcframework` | 重建 | 内嵌 dSYM 后重新提交 |
| `android/libs/Release/{arch}/libmarsxlog.so.sym` | 新增 | 独立符号文件 |
| `windows/libs/x64/Debug/xlog.pdb` | 新增 | Debug pdb |

---

## Task 1：简化 iOS podspec

**Files:**
- Modify: `samples/xlog_flutter/ios/xlog_flutter.podspec:33-42`

- [ ] **Step 1: 阅读当前 podspec 确认要删除的行范围**

  当前 `ios/xlog_flutter.podspec` 第 33–42 行是条件判断逻辑：
  ```ruby
  has_release = File.exist?(File.join(__dir__, 'libs/Release/MarsXlog.xcframework'))
  has_debug   = File.exist?(File.join(__dir__, 'libs/Debug/MarsXlog.xcframework'))

  if has_release || has_debug
    xcfw = has_debug ? 'libs/Debug/MarsXlog.xcframework' : 'libs/Release/MarsXlog.xcframework'
    s.vendored_frameworks = xcfw
  end
  ```

- [ ] **Step 2: 替换为单行固定引用**

  将上述 8 行（含注释）替换为：
  ```ruby
  s.vendored_frameworks = 'libs/Release/MarsXlog.xcframework'
  ```

  同时将上方注释块（第 28–32 行）更新为：
  ```ruby
  # ── Link against MarsXlog xcframework ────────────────────────────────────────
  # Build with: cd mars/mars && python build_xlog_ios.py [--config Release]
  # Expected: ios/libs/Release/MarsXlog.xcframework (with embedded dSYMs)
  # dSYMs are embedded in each XCFramework slice and auto-loaded by Xcode.
  ```

- [ ] **Step 3: 验证 podspec 语法**

  ```bash
  cd samples/xlog_flutter
  pod lib lint ios/xlog_flutter.podspec --allow-warnings 2>&1 | tail -5
  ```
  期望输出：`xlog_flutter passed validation` 或仅有 warnings（无 errors）。

  > **注意：** 如果当前 `ios/libs/Release/MarsXlog.xcframework` 不存在，lint 会报 framework 找不到的 warning，这是正常的（库文件在阶段二重建），不影响 podspec 语法正确性。

- [ ] **Step 4: Commit**

  ```bash
  cd samples/xlog_flutter
  git add ios/xlog_flutter.podspec
  git commit -m "refactor(ios): simplify podspec to use Release-only xcframework

  Remove Ruby conditional logic that selected Debug/Release at pod install time.
  CocoaPods runs before Xcode knows the build config, so the selection was
  meaningless. Follow Firebase/Sentry standard: Release-only + embedded dSYM."
  ```

---

## Task 2：简化 macOS podspec

**Files:**
- Modify: `samples/xlog_flutter/macos/xlog_flutter.podspec:32-41`

- [ ] **Step 1: 替换条件逻辑为单行**

  将 `macos/xlog_flutter.podspec` 第 32–41 行的条件判断替换为：
  ```ruby
  s.vendored_frameworks = 'libs/Release/MarsXlog.xcframework'
  ```

  更新上方注释（第 27–31 行）为：
  ```ruby
  # ── Link against MarsXlog xcframework ────────────────────────────────────────
  # Build with: cd mars/mars && python build_xlog_mac.py [--config Release]
  # Expected: macos/libs/Release/MarsXlog.xcframework (with embedded dSYMs)
  # dSYMs are embedded in each XCFramework slice and auto-loaded by Xcode.
  ```

- [ ] **Step 2: 验证语法**

  ```bash
  cd samples/xlog_flutter
  pod lib lint macos/xlog_flutter.podspec --allow-warnings 2>&1 | tail -5
  ```

- [ ] **Step 3: Commit**

  ```bash
  git add macos/xlog_flutter.podspec
  git commit -m "refactor(macos): simplify podspec to use Release-only xcframework

  Same rationale as iOS: remove Ruby conditional logic, follow industry standard
  of Release-only + embedded dSYM for Apple platform CocoaPods integration."
  ```

---

## Task 3：Windows CMakeLists 追加 .pdb 分发

**Files:**
- Modify: `samples/xlog_flutter/windows/CMakeLists.txt:61-74`

- [ ] **Step 1: 阅读当前 CMakeLists 确认插入位置**

  当前第 61–74 行：
  ```cmake
  set(XLOG_IMPORT_LIB
      "$<$<CONFIG:Debug>:${LIB_DIR}/x64/Debug/xlog.lib>$<$<NOT:$<CONFIG:Debug>>:${LIB_DIR}/x64/Release/xlog.lib>")
  set(XLOG_DLL
      "$<$<CONFIG:Debug>:${LIB_DIR}/x64/Debug/xlog.dll>$<$<NOT:$<CONFIG:Debug>>:${LIB_DIR}/x64/Release/xlog.dll>")

  target_link_libraries(xlog_flutter PRIVATE "${XLOG_IMPORT_LIB}")

  set(xlog_flutter_bundled_libraries
    $<TARGET_FILE:xlog_flutter>
    "${XLOG_DLL}"
    PARENT_SCOPE
  )
  ```

- [ ] **Step 2: 在 XLOG_DLL 定义之后、target_link_libraries 之前插入 XLOG_PDB**

  在 `set(XLOG_DLL ...)` 行之后追加：
  ```cmake
  set(XLOG_PDB
      "$<IF:$<CONFIG:Debug>,${LIB_DIR}/x64/Debug/xlog.pdb,${LIB_DIR}/x64/Release/xlog.pdb>")
  ```

  然后修改 `bundled_libraries` 块，在 `"${XLOG_DLL}"` 后追加 `"${XLOG_PDB}"`：
  ```cmake
  set(xlog_flutter_bundled_libraries
    $<TARGET_FILE:xlog_flutter>
    "${XLOG_DLL}"
    "${XLOG_PDB}"
    PARENT_SCOPE
  )
  ```

- [ ] **Step 3: 同时更新注释，明确 .pdb 为必需文件**

  将第 53–59 行注释中的 `(optional)` 改为必需：
  ```cmake
  #   copy cmake_build/Windows/Windows.out/win/xlog.pdb  -> windows/libs/x64/Release/xlog.pdb
  #
  #   cd mars && python build_windows.py --xlog --config Debug
  #   copy cmake_build/Windows/Windows.out/win/xlog.dll  -> windows/libs/x64/Debug/xlog.dll
  #   copy cmake_build/Windows/Windows.out/win/xlog.lib  -> windows/libs/x64/Debug/xlog.lib
  #   copy cmake_build/Windows/Windows.out/win/xlog.pdb  -> windows/libs/x64/Debug/xlog.pdb
  ```

- [ ] **Step 4: Commit**

  ```bash
  git add windows/CMakeLists.txt
  git commit -m "feat(windows): bundle xlog.pdb with plugin for Debug and Release

  Use CMake IF generator expression to select Debug/Release .pdb and include
  it in bundled_libraries. This causes Flutter to copy xlog.pdb to the build
  output dir alongside xlog.dll, enabling Visual Studio/WinDbg auto-loading
  of symbols without manual configuration."
  ```

---

## Task 4：更新 CODEBUDDY.md 文档

**Files:**
- Modify: `samples/xlog_flutter/CODEBUDDY.md`

- [ ] **Step 1: 更新预编译库路径表**

  找到"关键依赖前提"一节的表格，更新 iOS/macOS 的说明：

  ```markdown
  | iOS     | `ios/libs/Release/MarsXlog.xcframework` (含内嵌 dSYM) |
  | macOS   | `macos/libs/Release/MarsXlog.xcframework` (含内嵌 dSYM) |
  ```

  删除关于 `libs/Debug/` 路径的说明。

- [ ] **Step 2: 在"平台集成要点"节补充符号调试说明**

  在 iOS/macOS 条目后追加：
  ```markdown
  - **调试符号**：XCFramework 内嵌 dSYM，Xcode 自动加载符号；无需 podspec 额外配置
  ```

  在 Android 条目后追加：
  ```markdown
  - **调试符号（Debug build）**：`libmarsxlog.so` 未 strip，Android Studio 自动识别，可直接设 native 断点
  - **调试符号（Release build）**：`android/libs/Release/{arch}/libmarsxlog.so.sym` 需手动加载到 LLDB（Android Studio → Run Configurations → Debugger → Debug symbols directories）
  ```

  在 Windows 条目后追加：
  ```markdown
  - **调试符号**：`xlog.pdb` 随 Flutter build 输出目录自动分发，Visual Studio 自动识别
  ```

- [ ] **Step 3: 更新"构建 Mars 原生库"命令**

  更新 iOS/macOS 构建命令，移除 Debug 相关说明：
  ```bash
  # iOS（输出带 dSYM 的 MarsXlog.xcframework）
  python build_xlog_ios.py --xlog --config Release

  # macOS（同上）
  python build_xlog_mac.py --xlog --config Release
  ```

- [ ] **Step 4: Commit**

  ```bash
  git add CODEBUDDY.md
  git commit -m "docs: update CODEBUDDY.md for Release-only libs and debug symbol paths"
  ```

---

## Task 5：更新 build_xlog_ios.py — 内嵌 dSYM

**Files:**
- Modify: `mars/build_xlog_ios.py`（在 mars/ 根目录，非 samples/）

> **前提：** 此任务需要能运行 macOS 构建环境（Xcode Command Line Tools）。

- [ ] **Step 1: 理解当前 _create_xcframework 函数**

  当前 `_create_xcframework(os_framework, sim_framework, output_dir)` 函数（第 254–273 行）仅调用 `xcodebuild -create-xcframework`，不处理 dSYM。

  需要在 xcframework 创建后，将每个 slice 对应的 `.dSYM` 文件复制进去。

- [ ] **Step 2: 在 build_xlog_ios.py 中添加 embed_dsyms() 辅助函数**

  在 `_create_xcframework` 函数定义之后（约第 274 行），插入：

  ```python
  def _find_dsym(build_out_path: str, platform_label: str) -> Optional[str]:
      """Search for .dSYM bundle in the build output directory.

      xcodebuild produces MarsXlog.framework.dSYM alongside the .framework.
      We search common locations under build_out_path.
      """
      import glob as _glob
      patterns = [
          os.path.join(build_out_path, '**', 'MarsXlog.framework.dSYM'),
      ]
      for pattern in patterns:
          matches = _glob.glob(pattern, recursive=True)
          if matches:
              log.info('[dSYM] Found for %s: %s', platform_label, matches[0])
              return matches[0]
      log.warning('[dSYM] Not found for %s under %s', platform_label, build_out_path)
      return None


  def _embed_dsyms(xcframework_path: str, build_out_path: str) -> bool:
      """Embed dSYM bundles into the XCFramework slices.

      Apple's XCFramework format supports embedded dSYMs at:
          <xcframework>/<slice>/dSYMs/<name>.framework.dSYM/

      Xcode and CocoaPods automatically discover dSYMs in this location.

      Parameters
      ----------
      xcframework_path : str
          Path to the assembled MarsXlog.xcframework
      build_out_path : str
          CMake build root (e.g. cmake_build/iOS/Release) — parent of iOS.out

      Returns
      -------
      True if at least one dSYM was embedded; False if none found (non-fatal warning).
      """
      slice_dsym_map = {
          'ios-arm64':                 ('OS',        'arm64'),
          'ios-arm64_x86_64-simulator': ('SIMULATOR', 'x86_64'),
      }

      embedded_any = False
      for slice_dir_name, (platform_label, _arch) in slice_dsym_map.items():
          slice_path = os.path.join(xcframework_path, slice_dir_name)
          if not os.path.isdir(slice_path):
              log.warning('[dSYM] Slice directory not found: %s', slice_path)
              continue

          # Search for dSYM in the build output for this platform
          dsym_src = _find_dsym(build_out_path, platform_label)
          if dsym_src is None:
              continue

          dsym_dst_dir = os.path.join(slice_path, 'dSYMs')
          dsym_dst = os.path.join(dsym_dst_dir, 'MarsXlog.framework.dSYM')

          os.makedirs(dsym_dst_dir, exist_ok=True)
          if os.path.exists(dsym_dst):
              shutil.rmtree(dsym_dst)

          shutil.copytree(dsym_src, dsym_dst)
          log.info('[dSYM] Embedded: %s -> %s', dsym_src, dsym_dst)
          embedded_any = True

      return embedded_any
  ```

- [ ] **Step 3: 在 build_xlog_ios() 主函数末尾调用 _embed_dsyms()**

  在 `build_xlog_ios()` 函数的 `_create_xcframework(...)` 调用之后（约第 345 行），追加：

  ```python
      # ------------------------------------------------------------------ Embed dSYMs
      if config == 'Release':
          xcframework_path = os.path.join(config_outdir, XCFRAMEWORK_NAME)
          if not _embed_dsyms(xcframework_path, build_out_path):
              log.warning('No dSYMs embedded — consumers will have limited debug info')
          else:
              log.info('dSYMs embedded successfully')
  ```

- [ ] **Step 4: 验证函数已正确添加（静态检查）**

  ```bash
  cd mars/mars
  python -c "import build_xlog_ios; print('OK')"
  ```
  期望输出：`OK`（无 import 错误）。

  ```bash
  python -m py_compile build_xlog_ios.py && echo "Syntax OK"
  ```
  期望输出：`Syntax OK`

- [ ] **Step 5: Commit**

  ```bash
  git add mars/build_xlog_ios.py
  git commit -m "feat(build): embed dSYMs into iOS XCFramework for Release builds

  After assembling the XCFramework, automatically copy .dSYM bundles into
  each slice's dSYMs/ subdirectory per Apple's XCFramework format spec.
  Xcode and CocoaPods auto-discover embedded dSYMs, enabling consumers to
  see MarsXlog symbols in crash reports and debugger call stacks."
  ```

---

## Task 6：更新 build_xlog_mac.py — 内嵌 dSYM

**Files:**
- Modify: `mars/build_xlog_mac.py`

- [ ] **Step 1: 阅读 build_xlog_mac.py 的 _create_xcframework 函数**

  ```bash
  grep -n "_create_xcframework\|xcframework\|dSYM" mars/build_xlog_mac.py
  ```

- [ ] **Step 2: 从 build_xlog_ios.py 复用逻辑，适配 macOS slice 名称**

  macOS XCFramework 只有一个 slice：`macos-arm64_x86_64`，而非两个。

  在 `build_xlog_mac.py` 中添加与 iOS 相同的 `_find_dsym()` 和 `_embed_dsyms()` 函数，但修改 `slice_dsym_map`：

  ```python
  slice_dsym_map = {
      'macos-arm64_x86_64': ('ARM64_X86_64', 'arm64_x86_64'),
  }
  ```

- [ ] **Step 3: 在主构建函数末尾调用 _embed_dsyms()**

  与 iOS 相同的调用方式，在 `_create_xcframework(...)` 后追加：
  ```python
      if config == 'Release':
          xcframework_path = os.path.join(config_outdir, XCFRAMEWORK_NAME)
          if not _embed_dsyms(xcframework_path, build_out_path):
              log.warning('No dSYMs embedded — consumers will have limited debug info')
  ```

- [ ] **Step 4: 语法检查**

  ```bash
  cd mars/mars
  python -m py_compile build_xlog_mac.py && echo "Syntax OK"
  ```

- [ ] **Step 5: Commit**

  ```bash
  git add mars/build_xlog_mac.py
  git commit -m "feat(build): embed dSYMs into macOS XCFramework for Release builds"
  ```

---

## Task 7：更新 build_android.py — 生成 .so.sym

**Files:**
- Modify: `mars/build_android.py`

> **前提：** 需有 Android NDK 环境。

- [ ] **Step 1: 阅读 build_android.py 了解当前输出结构**

  ```bash
  grep -n "Release\|Debug\|libmarsxlog\|copy\|shutil\|outdir" mars/build_android.py | head -40
  ```

- [ ] **Step 2: 找到 Release 构建完成后的 .so 复制逻辑**

  定位将 `libmarsxlog.so` 复制到 `samples/xlog_flutter/android/libs/Release/{arch}/` 的代码行。

- [ ] **Step 3: 在复制 .so 之后，添加 .so.sym 提取逻辑**

  在复制 Release `.so` 之后追加（伪代码，按实际代码结构调整）：

  ```python
  def _extract_sym(so_path: str, sym_path: str, ndk_root: str) -> bool:
      """Extract debug symbols from .so into a separate .so.sym file.

      Uses llvm-objcopy --only-keep-debug to produce a symbols-only binary.
      The original .so is then stripped with llvm-strip --strip-all.

      Parameters
      ----------
      so_path : str
          Path to the full (unstripped) .so file
      sym_path : str
          Output path for the extracted symbols file
      ndk_root : str
          NDK root directory (e.g. $ANDROID_NDK_HOME)
      """
      import glob as _glob

      # Find llvm-objcopy in NDK toolchain
      pattern = os.path.join(ndk_root, 'toolchains', 'llvm', 'prebuilt', '*', 'bin', 'llvm-objcopy')
      matches = _glob.glob(pattern)
      if not matches:
          logging.warning('llvm-objcopy not found in NDK: %s', pattern)
          return False
      llvm_objcopy = matches[0]

      # Find llvm-strip
      llvm_strip = llvm_objcopy.replace('llvm-objcopy', 'llvm-strip')

      # Extract symbols
      ret = subprocess.run(
          [llvm_objcopy, '--only-keep-debug', so_path, sym_path],
          capture_output=True, text=True
      )
      if ret.returncode != 0:
          logging.warning('llvm-objcopy failed: %s', ret.stderr)
          return False

      # Strip original .so in-place
      ret = subprocess.run(
          [llvm_strip, '--strip-all', so_path],
          capture_output=True, text=True
      )
      if ret.returncode != 0:
          logging.warning('llvm-strip failed: %s', ret.stderr)
          # Non-fatal: stripped .so extraction succeeded

      logging.info('Symbol file: %s', sym_path)
      return True
  ```

  在 Release `.so` 复制完成后调用：
  ```python
  if config == 'Release':
      sym_path = so_dst_path + '.sym'
      ndk_root = os.environ.get('ANDROID_NDK_HOME', os.environ.get('NDK_ROOT', ''))
      if ndk_root:
          _extract_sym(so_dst_path, sym_path, ndk_root)
      else:
          logging.warning('ANDROID_NDK_HOME not set, skipping .so.sym extraction')
  ```

- [ ] **Step 4: 语法检查**

  ```bash
  cd mars/mars
  python -m py_compile build_android.py && echo "Syntax OK"
  ```

- [ ] **Step 5: Commit**

  ```bash
  git add mars/build_android.py
  git commit -m "feat(build): generate libmarsxlog.so.sym for Android Release builds

  After copying Release .so to plugin directory, extract debug symbols with
  llvm-objcopy --only-keep-debug and strip the .so with llvm-strip. The .sym
  file can be loaded in Android Studio LLDB for symbolicated call stacks."
  ```

---

## Task 8：更新 Windows 构建脚本 — 生成 Debug .pdb

**Files:**
- Modify: `mars/build_xlog_windows.py` 或 `mars/build_windows.py`（确认哪个生成 xlog）

- [ ] **Step 1: 确认生成 xlog.dll 的脚本**

  ```bash
  grep -l "xlog.dll\|xlog.lib\|xlog.pdb" mars/build_xlog_windows.py mars/build_windows.py 2>/dev/null
  ```

- [ ] **Step 2: 确认 Debug 构建时 .pdb 生成配置**

  MSVC 在 CMake Debug 构建时默认会生成 `.pdb`（需要 `/Zi` 或 `/ZI` 编译选项，Debug 构建默认启用）。检查构建脚本是否已正确传递 `--config Debug`：

  ```bash
  grep -n "Debug\|pdb\|config" mars/build_xlog_windows.py | head -20
  ```

- [ ] **Step 3: 确保 .pdb 被复制到插件目录**

  确认 Debug 构建完成后，脚本将 `xlog.pdb` 复制到 `samples/xlog_flutter/windows/libs/x64/Debug/`。

  若未复制，在脚本复制 Debug `xlog.dll`/`xlog.lib` 的逻辑附近追加：
  ```python
  # 复制 Debug pdb（供断点调试使用）
  pdb_src = os.path.join(build_output_dir, 'xlog.pdb')
  pdb_dst = os.path.join(plugin_debug_dir, 'xlog.pdb')
  if os.path.exists(pdb_src):
      shutil.copy2(pdb_src, pdb_dst)
      logging.info('Copied xlog.pdb -> %s', pdb_dst)
  else:
      logging.warning('xlog.pdb not found at %s', pdb_src)
  ```

- [ ] **Step 4: 语法检查**

  ```bash
  python -m py_compile mars/build_xlog_windows.py && echo "Syntax OK"
  ```

- [ ] **Step 5: Commit**

  ```bash
  git add mars/build_xlog_windows.py  # 或 build_windows.py
  git commit -m "feat(build): copy xlog.pdb for Debug Windows builds

  Ensure xlog.pdb is copied to windows/libs/x64/Debug/ alongside
  xlog.dll and xlog.lib. Combined with CMakeLists bundled_libraries
  change, this enables Visual Studio auto-loading of symbols."
  ```

---

## Task 9：删除 Debug 库目录（iOS/macOS）

> **前提：** Task 1 和 Task 2 已完成并提交。此任务在构建机上或本地执行。

- [ ] **Step 1: 确认 Debug 目录存在**

  ```bash
  ls -la samples/xlog_flutter/ios/libs/
  ls -la samples/xlog_flutter/macos/libs/
  ```

- [ ] **Step 2: 删除 Debug 目录**

  ```bash
  git rm -r samples/xlog_flutter/ios/libs/Debug/
  git rm -r samples/xlog_flutter/macos/libs/Debug/
  ```

- [ ] **Step 3: Commit**

  ```bash
  git commit -m "chore: remove Debug XCFramework binaries (~70MB)

  iOS and macOS now use Release-only XCFramework with embedded dSYMs.
  Debug libraries are no longer referenced by the podspecs and should
  not be committed to the repository."
  ```

---

## Task 10：重建 iOS XCFramework（含 dSYM）并提交

> **前提：** Task 5（build_xlog_ios.py 更新）已完成，macOS 构建环境可用。

- [ ] **Step 1: 执行构建**

  ```bash
  cd mars/mars
  python build_xlog_ios.py --config Release
  ```

  期望日志输出包含：
  ```
  [dSYM] Embedded: .../MarsXlog.framework.dSYM -> .../ios-arm64/dSYMs/MarsXlog.framework.dSYM
  [dSYM] Embedded: .../MarsXlog.framework.dSYM -> .../ios-arm64_x86_64-simulator/dSYMs/...
  dSYMs embedded successfully
  ```

- [ ] **Step 2: 验证 dSYM 结构**

  ```bash
  ls -la samples/xlog_flutter/ios/libs/Release/MarsXlog.xcframework/ios-arm64/dSYMs/
  # 应列出: MarsXlog.framework.dSYM/

  ls -la samples/xlog_flutter/ios/libs/Release/MarsXlog.xcframework/ios-arm64_x86_64-simulator/dSYMs/
  # 应列出: MarsXlog.framework.dSYM/
  ```

- [ ] **Step 3: 验证 DWARF 数据有效**

  ```bash
  xcrun dwarfdump -v \
    "samples/xlog_flutter/ios/libs/Release/MarsXlog.xcframework/ios-arm64/dSYMs/MarsXlog.framework.dSYM/Contents/Resources/DWARF/MarsXlog" \
    2>&1 | head -10
  # 应输出 DW_TAG_*, DW_AT_* 等 DWARF 信息，不应为空或报错
  ```

- [ ] **Step 4: Commit 新 XCFramework**

  ```bash
  cd samples/xlog_flutter
  git add ios/libs/Release/MarsXlog.xcframework
  git commit -m "build(ios): rebuild XCFramework with embedded dSYMs

  Rebuilt using updated build_xlog_ios.py which embeds dSYM bundles
  into each slice's dSYMs/ subdirectory per Apple XCFramework spec."
  ```

---

## Task 11：重建 macOS XCFramework（含 dSYM）并提交

> **前提：** Task 6（build_xlog_mac.py 更新）已完成。

- [ ] **Step 1: 执行构建**

  ```bash
  cd mars/mars
  python build_xlog_mac.py --config Release
  ```

- [ ] **Step 2: 验证 dSYM 结构**

  ```bash
  ls -la samples/xlog_flutter/macos/libs/Release/MarsXlog.xcframework/macos-arm64_x86_64/dSYMs/
  # 应列出: MarsXlog.framework.dSYM/
  ```

- [ ] **Step 3: 验证 DWARF 数据有效**

  ```bash
  xcrun dwarfdump -v \
    "samples/xlog_flutter/macos/libs/Release/MarsXlog.xcframework/macos-arm64_x86_64/dSYMs/MarsXlog.framework.dSYM/Contents/Resources/DWARF/MarsXlog" \
    2>&1 | head -10
  ```

- [ ] **Step 4: Commit**

  ```bash
  cd samples/xlog_flutter
  git add macos/libs/Release/MarsXlog.xcframework
  git commit -m "build(macos): rebuild XCFramework with embedded dSYMs"
  ```

---

## Task 12：重建 Android Release 库（含 .so.sym）并提交

> **前提：** Task 7（build_android.py 更新）已完成，Android NDK 环境可用，`ANDROID_NDK_HOME` 已设置。

- [ ] **Step 1: 执行构建**

  ```bash
  cd mars/mars
  python build_android.py --config Release
  ```
  （按实际脚本参数调整。）

- [ ] **Step 2: 验证 .so.sym 文件存在**

  ```bash
  ls -la samples/xlog_flutter/android/libs/Release/arm64-v8a/libmarsxlog.so.sym
  ls -la samples/xlog_flutter/android/libs/Release/armeabi-v7a/libmarsxlog.so.sym
  ```

- [ ] **Step 3: 验证 Release .so 已 strip（不含调试信息）**

  ```bash
  # 应输出符号极少（只剩导出符号），不含 DWARF
  nm samples/xlog_flutter/android/libs/Release/arm64-v8a/libmarsxlog.so | wc -l
  ```

- [ ] **Step 4: 验证 Debug .so 未 strip（含调试信息）**

  ```bash
  # 应输出大量符号
  nm samples/xlog_flutter/android/libs/Debug/arm64-v8a/libmarsxlog.so | wc -l
  ```

- [ ] **Step 5: Commit**

  ```bash
  cd samples/xlog_flutter
  git add android/libs/Release/
  git commit -m "build(android): add libmarsxlog.so.sym for Release builds

  Symbol files enable LLDB call stack symbolization for Release builds.
  Debug .so remains unstripped for direct Android Studio breakpoint debugging."
  ```

---

## Task 13：重建 Windows Debug 库（含 .pdb）并提交

> **前提：** Task 8（Windows 构建脚本更新）已完成，Windows 构建环境可用。

- [ ] **Step 1: 执行 Debug 构建**

  ```bash
  python mars/build_xlog_windows.py --xlog --config Debug
  # 或按实际脚本参数
  ```

- [ ] **Step 2: 验证 .pdb 文件存在**

  ```bash
  ls -la samples/xlog_flutter/windows/libs/x64/Debug/
  # 应列出: xlog.dll, xlog.lib, xlog.pdb
  ```

- [ ] **Step 3: Commit**

  ```bash
  cd samples/xlog_flutter
  git add windows/libs/x64/Debug/xlog.pdb
  git commit -m "build(windows): add xlog.pdb for Debug builds

  Enables Visual Studio and WinDbg to auto-load symbols when debugging
  Flutter apps that use xlog_flutter on Windows."
  ```

---

## Task 14：集成验收

- [ ] **Step 1: iOS — 验证 pod install 后 dSYM 存在**

  ```bash
  cd samples/xlog_flutter/example
  pod install
  find Pods/xlog_flutter -name "*.dSYM" -type d
  # 应找到: .../ios-arm64/dSYMs/MarsXlog.framework.dSYM
  #         .../ios-arm64_x86_64-simulator/dSYMs/MarsXlog.framework.dSYM
  ```

- [ ] **Step 2: macOS — 同上**

  ```bash
  find Pods/xlog_flutter -name "*.dSYM" -type d
  # 应找到: .../macos-arm64_x86_64/dSYMs/MarsXlog.framework.dSYM
  ```

- [ ] **Step 3: Android Debug — 验证 Android Studio 可见符号**

  在示例 app 的 `android/` 目录用 Android Studio 打开，设置 `Run Configuration → Debugger → Dual` 模式，在 `xlog_flutter.cpp` 中设断点，以 Debug 模式运行，确认断点命中。

- [ ] **Step 4: Windows Debug — 验证 Visual Studio 可见符号**

  在示例 app 的 `windows/` 目录用 Visual Studio 打开，Debug 构建，确认 xlog.pdb 在输出目录中，在 xlog_flutter.cpp 设断点并运行验证。

- [ ] **Step 5: 最终 Commit（如有验收中产生的修复）**

  ```bash
  git add .
  git commit -m "fix: address integration verification findings"
  ```

---

## 执行顺序建议

**可立即执行（无需构建环境）：** Task 1 → 2 → 3 → 4

**需要 macOS + Xcode：** Task 5 → 6 → 9 → 10 → 11

**需要 Android NDK：** Task 7 → 12

**需要 Windows + MSVC：** Task 8 → 13

**最后：** Task 14（所有平台库就绪后）
