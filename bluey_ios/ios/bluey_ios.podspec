Pod::Spec.new do |s|
  s.name             = 'bluey_ios'
  s.version          = '0.1.0'
  s.summary          = 'iOS implementation of Bluey BLE plugin'
  s.homepage         = 'https://github.com/neutrinographics/bluey'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Neutrinographics' => 'info@neutrinographics.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '12.0'
  s.swift_version    = '5.0'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386'
  }
  s.resource_bundles = {
    'bluey_ios_privacy' => ['Resources/PrivacyInfo.xcprivacy']
  }
end
