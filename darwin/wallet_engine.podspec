Pod::Spec.new do |s|
  s.name             = 'wallet_engine'
  s.version          = '0.1.0'
  s.summary          = 'Owned native signing bridge for wallet_engine.'
  s.description      = 'Pinned Wallet Core bridge used by the wallet_engine Flutter package.'
  s.homepage         = 'https://github.com/Joker-dev-hub/wallet_engine'
  s.license          = { :type => 'Apache-2.0', :file => '../LICENSE' }
  s.author           = { 'wallet_engine contributors' => 'opensource@example.invalid' }
  s.source           = {
    :git => ' https://github.com/CryptoKango/wallet_engine.git',
    :tag => s.version.to_s
  }

  s.source_files = 'wallet_engine/Sources/wallet_engine/**/*'
  s.vendored_frameworks = 'wallet_engine/WalletEngineCore.xcframework'

  s.ios.deployment_target = '14.0'
  s.ios.dependency 'Flutter'

  s.ios.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386'
  }
  s.swift_version = '5.9'
end
