#
# Run `pod lib lint xlog_flutter.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'xlog_flutter'
  s.version          = '0.0.1'
  s.summary          = 'Flutter FFI plugin for mars xlog (iOS).'
  s.description      = <<-DESC
Flutter FFI plugin for the mars xlog logging library. Uses a prebuilt
Universal Static Framework covering iOS device (arm64) and simulator (x86_64).
                       DESC
  s.homepage         = 'https://github.com/Tencent/mars'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Tencent' => 'mars@tencent.com' }

  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'

  # Prebuilt Universal Static Framework (device arm64 + simulator x86_64).
  # Build it first with: python mars/xlog/build_ios.py --config Release
  # xlog.framework bundles xlog + comm + boost + zstd + OpenSSL (all statically linked).
  s.vendored_frameworks = 'libs/Release/xlog.framework'
  s.preserve_paths = 'libs/**/*'

  s.dependency 'Flutter'
  s.platform = :ios, '12.0'

  # xlog.framework links against these system frameworks internally.
  s.frameworks = 'Foundation', 'CoreFoundation'
  s.libraries  = 'z'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE'                        => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]'  => 'i386',
  }
  s.swift_version = '5.0'
end
