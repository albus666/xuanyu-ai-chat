Pod::Spec.new do |s|
  s.name             = 'AMap3DMap'
  s.version          = '11.1.000'
  s.summary          = 'MAMapKit 3D for iOS（仓库内 vendored，无网络下载）'
  s.description      = '3D Map SDK for iOS by Autonavi. Framework 随仓库提交，供 CI 离线集成。'
  s.homepage         = 'https://lbs.amap.com/'
  s.license          = { :type => 'Copyright', :text => "Copyright © 2014 AutoNavi.\n" }
  s.author           = { 'lbs.amap.com' => 'https://lbs.amap.com/' }
  s.source           = { :path => '.' }
  s.platform         = :ios, '9.0'
  s.requires_arc     = true
  s.source_files     = 'MAMapKit.framework/**/*.{h}'
  s.public_header_files = 'MAMapKit.framework/Headers/*.h'
  s.resources        = 'MAMapKit.framework/AMap.bundle'
  s.vendored_frameworks = 'MAMapKit.framework'
  s.frameworks       = 'QuartzCore', 'CoreLocation', 'SystemConfiguration', 'CoreTelephony', 'Security', 'OpenGLES', 'CoreText', 'CoreGraphics', 'GLKit'
  s.libraries        = 'z', 'c++'
  s.xcconfig         = { 'ARCHS' => '$(ARCHS_STANDARD)' }
  s.dependency 'AMapFoundation', '>= 1.8.6'
end
