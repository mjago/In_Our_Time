require 'bundler/gem_tasks'
require 'rake/testtask'
require 'rake/version_task'
require 'yard'

Rake::VersionTask.new

Rake::TestTask.new do |t|
  t.pattern = "test/test_*.rb"
end

YARD::Rake::YardocTask.new do |t|
  t.files   = ['lib/**/*.rb']
  t.options = ['--any', '--extra', '--opts']
end
