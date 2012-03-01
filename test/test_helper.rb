coverage_tool = :simplecov if ENV['RVC_COVERAGE']

case coverage_tool
when :simplecov
  require 'simplecov'
  SimpleCov.start
when :cover_me
  require 'cover_me'
end

require 'test/unit'
require 'rvc'
