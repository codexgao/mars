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

  # The xlog wrapper source and its bundled headers
  s.source_files = [
    'Classes/**/*',
    '../src/xlog_flutter.cpp',
    '../src/xlog_flutter.h',
  ]

  # Prebuilt xcframework (build with: cd mars && python build_osx.py)
  # Place output at: macos/libs/MarsXlog.xcframework
  xcframework_path = 'libs/MarsXlog.xcframework'
  if File.exist?(File.join(__dir__, xcframework_path))
    s.vendored_frameworks = xcframework_path
  end

  s.pod_target_xcconfig = {
    'DEFINES_MODULE'       => 'YES',
    'HEADER_SEARCH_PATHS'  => '"$(PODS_TARGET_SRCROOT)/../include"',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
  }

  s.dependency 'FlutterMacOS'
  s.platform = :osx, '10.14'
  s.swift_version = '5.0'
end
