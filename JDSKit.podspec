Pod::Spec.new do |s|
  s.name         = "JDSKit"
  s.version      = "1.2.3"
  s.summary      = "JDS Kit aggregates a core functionality to sync and store data using spiked-JSON-API protocol :D"
  s.homepage     = "https://github.com/Railsreactor/json-data-sync-swift" 
  s.license      = "MIT"  
  s.author       = { "Igor Reshetnikov" => "igor.reshetnikov.91@gmail.com" }  
  s.requires_arc = true
  s.platform     = :ios
  s.ios.deployment_target = '8.0'
  s.source       = { :git => "https://github.com/Railsreactor/json-data-sync-swift.git", :tag => "1.2.3" }
  s.source_files  = "JDSKit", "JDSKit/**/*.{sh,h,m,swift}"    
  s.preserve_paths = "JDSKit/InitialModel.xcdatamodeld"
  s.resource = "JDSKit/InitialModel.xcdatamodeld"
  s.frameworks = "UIKit", "Foundation"
  s.dependency 'CocoaLumberjack/Swift', '~> 2.2.0'
  s.dependency 'PromiseKit', '~> 3.5'
  s.dependency 'SwiftyJSON', '~> 2.4'
  s.pod_target_xcconfig = { 'SWIFT_OPTIMIZATION_LEVEL' => '-Onone', 'GCC_OPTIMIZATION_LEVEL' => '0' }
end

