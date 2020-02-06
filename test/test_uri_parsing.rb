require 'test_helper'
require 'mocha'
require 'openssl'
require 'ostruct'

class URIParsingTest < Test::Unit::TestCase
  PROMPT_PASSWORD_MODULE = <<-EOS
  def prompt_password
    'prompted'
  end
  EOS

  def setup
    @shell = RVC::Shell.new
    @shell.reload_modules false

    @shell.cmds.vim.load_code PROMPT_PASSWORD_MODULE, 'inline'

    @vim = OpenStruct.new
    @vim.serviceContent = OpenStruct.new
    @vim.serviceContent.about = OpenStruct.new
    @vim.serviceContent.about.apiVersion = '5.0'
    @vim.serviceContent.sessionManager = OpenStruct.new
  end

  def teardown
    @shell = nil
    @vim = nil
  end

  def expect_parse_uri uri, username, password, host, port
    RbVmomi::VIM.stubs(:new).with(has_entries(:host => host, :port => port)).returns(@vim)
    @vim.serviceContent.sessionManager.stubs(:Login).with(has_entries(:userName => username, :password => password))
    @vim.stubs(:define_singleton_method)
    @shell.cmds.vim.connect(uri, {})
  end

  def expect_parse_uri_with_env env_user, env_password, uri, username, password, host, port
    ENV['RBVMOMI_USER'] = env_user
    ENV['RBVMOMI_PASSWORD'] = env_password
    expect_parse_uri uri, username, password, host, port
  ensure
    ENV['RBVMOMI_USER'] = nil
    ENV['RBVMOMI_PASSWORD'] = nil
  end

  def test_only_host
    expect_parse_uri "host.example.com", "root", "prompted", "host.example.com", 443
  end

  def test_scheme
    expect_parse_uri "vim://host", "root", "prompted", "host", 443
  end

  def test_port
    expect_parse_uri "host:80", "root", "prompted", "host", 80
  end

  def test_user
    expect_parse_uri "user@host", "user", "prompted", "host", 443
  end

  def test_user_and_password
    expect_parse_uri "user:password@host", "user", "password", "host", 443
  end

  def test_user_and_password_and_port
    expect_parse_uri "user:password@host:80", "user", "password", "host", 80
  end

  def test_domain_user
    expect_parse_uri "domain\\user@host", "domain\\user", "prompted", "host", 443
  end

  def test_domain_user_uri_escaped
    expect_parse_uri "domain%5Cuser:pw@host", "domain\\user", "pw", "host", 443
  end

  def test_user_and_password_escaped
    expect_parse_uri "domain%5cuser:pw%2f%40%23%3C%3e@host", "domain\\user", "pw/@#<>", "host", 443
  end

  def test_env_user_and_pw_in_uri
    expect_parse_uri_with_env "env\\user", "envpw@#", "domain%5cuser:pw%2f%40%23%3C%3e@host", "domain\\user", "pw/@#<>", "host", 443
  end

  def test_env_user_in_uri
    expect_parse_uri_with_env "env\\user", "envpw@#", "domain%5cuser@host", "domain\\user", "envpw@#", "host", 443
  end

  def test_env_just_host
    expect_parse_uri_with_env "env\\user", "envpw@#", "host", "env\\user", "envpw@#", "host", 443
  end
end
