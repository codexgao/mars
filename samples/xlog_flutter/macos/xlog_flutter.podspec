#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint xlog_flutter.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'xlog_flutter'
  s.version          = '0.0.1'
  s.summary          = 'Flutter FFI plugin for mars xlog.'
  s.description      = <<-DESC
Flutter FFI plugin for mars xlog multi-instance logging library.
Uses a prebuilt libxlog.dylib (Universal Binary: arm64 + x86_64).
Build with: python3 mars/xlog/build_macos.py --config Release
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }

  s.source           = { :path => '.' }

  # Classes/ contains a forwarder xlog_flutter.c — required by Flutter FFI plugin structure.
  s.source_files = 'Classes/**/*'

  # Prebuilt libxlog.dylib (Universal Binary: arm64 + x86_64).
  # Build with: python3 mars/xlog/build_macos.py --config Release
  s.vendored_libraries = 'libs/Release/libxlog.dylib'
  s.preserve_paths = 'libs/**/*'

  s.dependency 'FlutterMacOS'

  s.platform = :osx, '10.13'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'OTHER_LDFLAGS' => '$(inherited) -rpath @loader_path/Frameworks'
  }
  s.swift_version = '5.0'
end
