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
  # For details, see: ios/Classes/xlog_flutter.cpp

  s.source_files = 'Classes/**/*'
  s.public_header_files = 'Classes/**/*.h'

  # ── Link against MarsXlog xcframework ────────────────────────────────────────
  # Build with: cd mars/mars && python build_xlog_ios.py [--config Release|Debug]
  # Expected: ios/libs/Release/MarsXlog.xcframework, ios/libs/Debug/MarsXlog.xcframework
  # A build script keeps ios/libs/MarsXlog.xcframework symlink pointing to the right variant.

  has_release = File.exist?(File.join(__dir__, 'libs/Release/MarsXlog.xcframework'))
  has_debug   = File.exist?(File.join(__dir__, 'libs/Debug/MarsXlog.xcframework'))

  if has_release || has_debug
    # Pick one xcframework at pod-install time (Ruby runs here, not at build time).
    # During pod install the CONFIGURATION variable is not available, so we
    # prefer Debug when it exists (developer workflow), otherwise Release.
    xcfw = has_debug ? 'libs/Debug/MarsXlog.xcframework' : 'libs/Release/MarsXlog.xcframework'
    s.vendored_frameworks = xcfw
  end

  s.pod_target_xcconfig = {
    'DEFINES_MODULE'                       => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'arm64',
    'HEADER_SEARCH_PATHS'                  => '$(PODS_TARGET_SRCROOT)/../include $(PODS_TARGET_SRCROOT)/../src',
    'CLANG_CXX_LANGUAGE_STANDARD'          => 'c++17',
    # Allow undefined symbols that are only called at verbose log level
    # (e.g., mars::boot::Context::GetContextId from alarm_manager.cc)
    # These are never called in typical xlog usage
    'OTHER_LDFLAGS'                        => '$(inherited) -undefined dynamic_lookup',
  }

  s.frameworks = 'SystemConfiguration', 'CFNetwork', 'CoreTelephony', 'CoreLocation', 'Security'
  s.libraries  = 'z', 'resolv'
  s.dependency 'Flutter'
  s.platform = :ios, '12.0'
  s.swift_version = '5.0'
end
