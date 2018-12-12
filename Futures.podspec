Pod::Spec.new do |s|
  s.name         = "Futures"
  s.version      = "1.0.0"
  s.summary      = "Futures library for iOS"
  s.homepage     = "https://github.com/mrdepth/Futures"
  s.license      = "MIT"
  s.author       = { "Shimanski Artem" => "shimanski.artem@gmail.com" }
  s.source       = { :git => "https://github.com/mrdepth/Futures.git", :branch => "master" }
  s.source_files = "Source/*.swift"
  s.platform     = :ios
  s.ios.deployment_target = "9.0"
  s.swift_version = "4.2"
end
