begin
  require 'jeweler'
  Jeweler::Tasks.new do |gem|
    gem.name = "rvc"
    gem.summary = "vSphere console UI"
    #gem.description = ""
    gem.email = "rlane@vmware.com"
    gem.homepage = "https://github.com/vmware/rvc"
    gem.authors = ["Rich Lane", "Christian Dickmann"]
    gem.add_dependency 'rbvmomi', '>= 1.6.0'
    gem.add_dependency 'trollop', '>= 1.16.2'
    gem.add_dependency 'backports', '>= 1.18.2'
    gem.add_dependency 'highline', '>= 1.6.1'
    gem.add_dependency 'zip', '>= 2.0.2'
    gem.add_dependency 'terminal-table', '>= 1.4.2'
    #gem.add_dependency 'ffi', '>= 1.0.7'
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

begin
  # HACK rvc needs to be installed as a gem
  require 'rvc'
  require 'ocra'
  desc 'Compile into a win32 executable'
  task :exe do
    sh "ocra bin/rvc"
  end
rescue LoadError
  puts "OCRA not available. Install it with: gem install ocra"
end
