#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint xlog_flutter.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'xlog_flutter'
  s.version          = '0.0.1'
  s.summary          = 'Flutter FFI plugin wrapping the mars xlog logging library.'
  s.description      = 'Provides Flutter apps with high-performance, reliable logging via WeChat Mars xlog.'
  s.homepage         = 'https://github.com/Tencent/mars'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Tencent' => 'mars@tencent.com' }

  s.source           = { :path => '.' }

  # ── Compile xlog_flutter from source ─────────────────────────────────────────
  # The actual source code is at ../src/xlog_flutter.cpp (shared across platforms).
  # CocoaPods cannot directly include source_files from outside the pod directory.
  # Solution: Use a forwarder file in Classes/ that includes ../src/xlog_flutter.cpp
  # via relative path. This way CocoaPods sees source_files='Classes/**/*' which
  # is valid, and the build system includes the actual implementation.
  #
  # For details, see: macos/Classes/xlog_flutter.mm

  s.source_files = 'Classes/**/*'

  # ── Link against MarsXlog xcframework ────────────────────────────────────────
  # Build with: cd mars && python build_xlog_mac.py --config Release
  # Expected: macos/libs/Release/MarsXlog.xcframework (with embedded dSYMs)
  # dSYMs are embedded in each XCFramework slice and auto-loaded by Xcode.

  s.vendored_frameworks = 'libs/Release/MarsXlog.xcframework'

  s.libraries = 'z'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE'       => 'YES',
    'HEADER_SEARCH_PATHS'  => '$(PODS_TARGET_SRCROOT)/../include $(PODS_TARGET_SRCROOT)/../src',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
  }

  s.dependency 'FlutterMacOS'
  s.platform = :osx, '10.14'
  s.swift_version = '5.0'
end
