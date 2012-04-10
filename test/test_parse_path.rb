require 'test_helper'

class ParsePathTest < Test::Unit::TestCase
  def test_empty
    els, absolute, trailing_slash = RVC::Path.parse('')
    assert_equal [], els
    assert_equal false, absolute
    assert_equal false, trailing_slash
  end

  def test_root
    els, absolute, trailing_slash = RVC::Path.parse('/')
    assert_equal [], els
    assert_equal true, absolute
    assert_equal true, trailing_slash
  end

  def test_normal
    els, absolute, trailing_slash = RVC::Path.parse('/foo/bar')
    assert_equal %w(foo bar), els
    assert_equal true, absolute
    assert_equal false, trailing_slash

    els, absolute, trailing_slash = RVC::Path.parse('/foo/bar/')
    assert_equal %w(foo bar), els
    assert_equal true, absolute
    assert_equal true, trailing_slash

    els, absolute, trailing_slash = RVC::Path.parse('foo/bar/')
    assert_equal %w(foo bar), els
    assert_equal false, absolute
    assert_equal true, trailing_slash

    els, absolute, trailing_slash = RVC::Path.parse('foo/bar')
    assert_equal %w(foo bar), els
    assert_equal false, absolute
    assert_equal false, trailing_slash
  end
end

