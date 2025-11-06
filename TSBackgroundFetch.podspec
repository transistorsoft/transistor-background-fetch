#
# Be sure to run `pod lib lint TSBackgroundFetch.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'TSBackgroundFetch'
  s.version             = '4.0.0'
  s.source_files        = 'ios/TSBackgroundFetch/TSBackgroundFetch/*.{h,m}'
  s.vendored_frameworks = 'TSBackgroundFetch.xcframework.xcframework'
  s.documentation_url   = 'https://github.com/transistorsoft/transistor-background-fetch/docs/ios'
  s.frameworks          = 'UIKit'
  s.weak_frameworks     = 'BackgroundTasks'
end
