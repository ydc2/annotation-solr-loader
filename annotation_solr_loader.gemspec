# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'annotation_solr_loader/version'

Gem::Specification.new do |spec|
  spec.name          = "annotation_solr_loader"
  spec.version       = "0.0.0"
  spec.authors       = ["rlechich"]
  spec.email         = ["roy.lechich@yale.edu"]
  spec.summary       = %q{Load data from IIIF annotations to SOLR}
  spec.description   = %q{Load data from IIIF annotations to SOLR for use in Blacklight discovery app}
  spec.homepage      = "http://desmmsearch.ydc2.yale.edu"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.6"
  spec.add_development_dependency "rake", '~> 0'
  spec.add_dependency "rsolr", '~> 1.0', '>= 1.0.10'

end
