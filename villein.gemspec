# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'villein/version'

Gem::Specification.new do |spec|
  spec.name          = "villein"
  spec.version       = Villein::VERSION
  spec.authors       = ["Shota Fukumori (sora_h)"]
  spec.email         = ["sorah@cookpad.com", "her@sorah.jp"]
  spec.summary       = %q{Use `serf` (serfdom.io) from Ruby.}
  spec.description   = %q{Use serf (http://www.serfdom.io/) from Ruby.}
  spec.homepage      = ""
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "rspec", "2.14.1"
  spec.add_development_dependency "bundler", "~> 1.5"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rdoc"
end
