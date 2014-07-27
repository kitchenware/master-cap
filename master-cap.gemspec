# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)

Gem::Specification.new do |s|

  s.name        = "master-cap"
  s.version     = "0.1"
  s.platform    = Gem::Platform::RUBY
  s.authors     = ["Bertrand Paquet"]
  s.email       = ["bertrand.paquet@gmail.com"]
  s.homepage    = "http://github.com/bpaquet/master-cap"
  s.summary     = "Capistrano tasks designed to work with master-chef"
  s.description = "Capistrano tasks designed to work with master-chef"
  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]
  s.extra_rdoc_files = [
    "Readme.markdown"
  ]

  s.specification_version = 3
  s.add_runtime_dependency(%q<capistrano>, ["~> 2"])
  s.add_runtime_dependency(%q<json>)
  s.add_runtime_dependency(%q<erubis>)
  s.add_runtime_dependency(%q<deep_merge>)
  s.add_runtime_dependency(%q<peach>)

  s.add_development_dependency(%q<foodcritic>)
end