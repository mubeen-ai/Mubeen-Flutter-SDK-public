# mubeen_flutter.podspec
#
# In-repo path: ios/mubeen_flutter.podspec
#
# Serves the **CocoaPods** resolver. `ios/mubeen_flutter/Package.swift` serves the
# **Swift Package Manager** resolver; Flutter picks whichever the host app has enabled
# and both must stay in sync (same sources, same SDK version).
#
# Why we vendor the xcframework instead of depending on the published `MubeenDeviceSDK`
# pod: CocoaPods trunk goes **read-only on 2026-12-02**, so publishing (or re-publishing)
# our own pod there is permanently off the table, and we do not want a plugin install to
# depend on a registry that is being frozen. The binary is 2.1 MB, small enough to commit
# directly — no Git LFS, no install-time download, no network flake in a client's CI.
# `fetch-xcframework.sh` is how the committed copy is produced and refreshed.

Pod::Spec.new do |s|
  s.name             = 'mubeen_flutter'
  s.version          = '0.1.6'
  s.summary          = 'Flutter plugin for the Mubeen device-intelligence SDKs.'
  s.description      = <<-DESC
Flutter wrapper around MubeenDeviceSDK 2.0 (iOS) — persistent UUIDv7 device id plus
one-way device-fingerprint submission with SHA-256 hashed linkage metadata.
                       DESC
  s.homepage         = 'https://github.com/mubeen-ai/Mubeen-Flutter-SDK-public'
  s.license          = { :type => 'Proprietary', :text => 'Mubeen SDK License. Copyright 2026 Mubeen AI. See LICENSE in the repository root.' }
  s.author           = { 'Mubeen' => 'engineering@mubeen.ai' }

  s.source           = { :path => '.' }
  # Flutter's SPM-compatible plugin layout: one source tree, two manifests.
  s.source_files     = 'mubeen_flutter/Sources/mubeen_flutter/**/*.swift'

  # Same privacy manifest Package.swift ships via `resources:`; the bundle naming follows
  # Flutter's plugin guidance for CocoaPods.
  s.resource_bundles = { 'mubeen_flutter_privacy' => ['mubeen_flutter/Sources/mubeen_flutter/PrivacyInfo.xcprivacy'] }

  s.dependency 'Flutter'
  s.platform         = :ios, '15.0'
  s.swift_version    = '5.10'

  # The committed binary. `vendored_frameworks` is what links and embeds it;
  # `preserve_paths` is what stops CocoaPods pruning the directory out of the sandbox
  # during `pod install` (an .xcframework is a directory of directories, and without this
  # the non-referenced slice can be dropped).
  s.vendored_frameworks = 'Frameworks/MubeenDeviceSDK.xcframework'
  s.preserve_paths      = 'Frameworks/MubeenDeviceSDK.xcframework'

  # Frameworks the SDK links against (mirrors MubeenDeviceSDK.podspec:26-27).
  s.frameworks       = 'Foundation', 'Security', 'CryptoKit', 'Network', 'DeviceCheck', 'UIKit'

  s.pod_target_xcconfig = {
    # Flutter plugin template default; also required for `import MubeenDeviceSDK`
    # to resolve against a vendored binary module.
    'DEFINES_MODULE' => 'YES',
    # Points the compiler at the vendored directory. CocoaPods adds this for vendored
    # frameworks in most configurations, but not reliably for an .xcframework inside a
    # plugin consumed by path, so set it explicitly.
    'FRAMEWORK_SEARCH_PATHS' => '$(inherited) "$(PODS_TARGET_SRCROOT)/Frameworks"',
    # The SDK ships as a Swift module; the host target needs the same flag when the app
    # is built with library evolution off (Flutter's default).
    'CLANG_ENABLE_MODULES' => 'YES'
  }

# No EXCLUDED_ARCHS here, deliberately. It used to be set in both pod_target_xcconfig and
# user_target_xcconfig, excluding i386 on the simulator. user_target_xcconfig is merged across
# every pod in the client's app, and CocoaPods aborts `pod install` when two pods give one
# singular setting different values - so a client with any other pod that sets
# EXCLUDED_ARCHS in its own user_target_xcconfig would have failed to install, over a
# setting they never wrote. It could only ever collide: no i386 simulator slice has existed since Xcode 12, and
# this plugin requires Xcode 16.
end
