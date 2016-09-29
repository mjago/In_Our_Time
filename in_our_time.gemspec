# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)



Gem::Specification.new do |spec|
  spec.name        = 'in_our_time'
  spec.version     = File.read('VERSION')
  spec.date        = Date.parse(Time.now.to_s).to_s
  spec.authors     = ["Martyn Jago"]
  spec.email       = ["martyn.jago@btinternet.com"]
  spec.description = "In Our Time Player"
  spec.summary     = "Select, play, and download BBC \'In Our Time\' podcasts - all from the command line"
  spec.homepage    = 'https://github.com/mjago/In_Our_Time'
  spec.files       = `git ls-files`.split($/)
  spec.executables = "iot"
  spec.bindir      = 'bin'
  spec.license     = 'MIT'

  spec.require_paths = ["lib"]
  spec.required_ruby_version = '>= 2.0.0'
  spec.add_runtime_dependency 'oga', '~> 2.2'
  spec.add_runtime_dependency 'colorize', '>= 0.8.1'
  spec.add_development_dependency 'version', '>= 1.0.0'
end
