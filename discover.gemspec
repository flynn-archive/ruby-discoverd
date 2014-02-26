# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'discover/version'

Gem::Specification.new do |spec|
  spec.name          = "discover"
  spec.version       = Discover::VERSION
  spec.authors       = ["Jonathan Rudenberg", "Lewis Marshall"]
  spec.email         = ["jonathan@titanous.com", "lewis@lmars.net"]
  spec.summary       = %q{A discoverd client for Ruby}
  spec.description   = %q{A discoverd client for Ruby}
  spec.homepage      = ""
  spec.license       = "BSD"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_dependency 'celluloid'
  spec.add_dependency 'rpcplus'
  spec.add_development_dependency "bundler"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "minitest", ">= 5.2.3"
end
