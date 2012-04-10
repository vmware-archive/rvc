require 'test_helper'
require 'rvc/uri_parser'

class UriTest < Test::Unit::TestCase
  def test_only_host
    uri = RVC::URIParser.parse "host.example.com"
    assert_equal "//host.example.com", uri.to_s
  end

  def test_scheme
    uri = RVC::URIParser.parse "vim://host"
    assert_equal "vim://host", uri.to_s
  end

  def test_port
    uri = RVC::URIParser.parse "host:80"
    assert_equal "//host:80", uri.to_s
  end

  def test_user
    uri = RVC::URIParser.parse "user@host"
    assert_equal "//user@host", uri.to_s
  end

  def test_user_and_password
    uri = RVC::URIParser.parse "user:password@host"
    assert_equal "//user:password@host", uri.to_s
  end

  def test_user_and_password_and_port
    uri = RVC::URIParser.parse "user:password@host:80"
    assert_equal "//user:password@host:80", uri.to_s
  end
end
