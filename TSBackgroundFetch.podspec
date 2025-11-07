#
# Be sure to run `pod lib lint TSBackgroundFetch.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#
Pod::Spec.new do |s|
  s.name                = 'TSBackgroundFetch'
  s.version             = '4.0.1'
  s.vendored_frameworks = 'TSBackgroundFetch.xcframework'
  s.documentation_url   = 'https://github.com/transistorsoft/transistor-background-fetch/docs/ios'
  s.frameworks          = 'UIKit'
  s.weak_frameworks     = 'BackgroundTasks'
  s.source              = { :http => 'https://github.com/transistorsoft/transistor-background-fetch/releases/download/4.0.1/TSBackgroundFetch.xcframework.zip' }
  s.resource_bundles = { 'TSBackgroundFetch' => ['ios/TSBackgroundFetch/TSBackgroundFetch/PrivacyInfo.xcprivacy'] }
  s.homepage            = 'https://github.com/transistorsoft/transistor-background-fetch'
  s.license             = { :type => 'MIT', :file => 'LICENSE' }
  s.summary             = 'Background fetch & periodic background tasks for iOS.'
  s.description         = 'Lightweight, open-source Background Fetch that wraps BGTaskScheduler / background fetch to deliver reliable periodic callbacks.'
  s.author              = { 'Transistor Software' => 'info@transistorsoft.com' }
  s.ios.deployment_target = '12.0'
  s.static_framework    = true
  s.pod_target_xcconfig = { 'BUILD_LIBRARY_FOR_DISTRIBUTION' => 'YES' }
end