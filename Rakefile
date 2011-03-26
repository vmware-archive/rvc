begin
  require 'jeweler'
  Jeweler::Tasks.new do |gem|
    gem.name = "rvc"
    gem.summary = "vSphere console UI"
    #gem.description = ""
    gem.email = "rlane@vmware.com"
    #gem.homepage = ""
    gem.authors = ["Rich Lane"]
    gem.add_dependency 'rbvmomi', '>= 1.2.2'
    gem.add_dependency 'trollop', '>= 1.16.2'
    gem.add_dependency 'backports', '>= 1.18.2'
    gem.add_dependency 'ffi', '>= 1.0.7'
  end
rescue LoadError
  puts "Jeweler not available. Install it with: gem install jeweler"
end

require 'rake/testtask'
Rake::TestTask.new do |t|
  t.libs << "test"
  t.test_files = FileList['test/test_*.rb']
  t.verbose = true
  t.ruby_opts << "-rubygems"
end
 
begin
  require 'rcov/rcovtask'
  desc 'Measures test coverage using rcov'
  Rcov::RcovTask.new do |rcov|
    rcov.pattern    = 'test/test_*.rb'
    rcov.output_dir = 'coverage'
    rcov.verbose    = true
    rcov.libs << "test"
    rcov.rcov_opts << '--exclude "gems/*"'
  end
rescue LoadError
  puts "Rcov not available. Install it with: gem install rcov"
end
