require 'test/unit'
require 'rvc'
require 'inventory_fixtures'

class FSTest < Test::Unit::TestCase
  NodeB = FixtureNode.new 'B'
  NodeC = FixtureNode.new 'C'
  NodeA = FixtureNode.new('A', 'b' => NodeB, 'c' => NodeC)
  Root = FixtureNode.new('ROOT', 'a' => NodeA)

  def setup
    @context = RVC::FS.new Root
  end

  def teardown
    @context = nil
  end

  def test_new
    assert_equal Root, @context.cur
    assert_equal "/", @context.display_path
    assert_equal 0, @context.marks.size
    assert_equal [''], @context.loc.path
    assert_equal [['', Root]], @context.loc.stack
  end

  def test_lookup_simple
    assert_equal nil, @context.lookup('nonexistent')
    assert_equal Root, @context.lookup('.')
    assert_equal Root, @context.lookup('..')
    assert_equal Root, @context.lookup('...')
    assert_equal NodeA, @context.lookup('a')
    assert_equal NodeB, @context.lookup('a/b')
    assert_equal NodeC, @context.lookup('a/b/../c')
    assert_equal NodeC, @context.lookup('a/b/.../c')
  end

  def test_lookup_loc_nonexistent
    loc = @context.lookup_loc 'nonexistent'
    assert_equal nil, loc
  end

  def test_lookup_loc_simple
    %w(a /a ./a ./a/.).each do |path|
      loc = @context.lookup_loc path
      assert_equal NodeA, loc.obj
      assert_equal ['', 'a'], loc.path
      assert_equal [['', Root], ['a', NodeA]], loc.stack
    end

    %w(a/b /a/b ./a/b /a/b/.).each do |path|
      loc = @context.lookup_loc path
      assert_equal NodeB, loc.obj
      assert_equal ['', 'a', 'b'], loc.path
      assert_equal [['', Root], ['a', NodeA], ['b', NodeB]], loc.stack
    end
  end

  def test_lookup_loc_parent
    loc = @context.lookup_loc '..'
    assert_equal [['', Root]], loc.stack

    loc = @context.lookup_loc 'a/..'
    assert_equal [['', Root]], loc.stack

    loc = @context.lookup_loc 'a/b/..'
    assert_equal [['', Root], ['a', NodeA]], loc.stack
  end

  def test_lookup_loc_realparent
    loc = @context.lookup_loc '...'
    assert_equal [['', Root]], loc.stack

    loc = @context.lookup_loc 'a/...'
    assert_equal [['', Root], ['a', NodeA], ['...', Root]], loc.stack

    loc = @context.lookup_loc 'a/b/...'
    assert_equal [['', Root], ['a', NodeA], ['b', NodeB], ['...', NodeA]], loc.stack
  end

  def test_lookup_loc_mark
    b_loc = @context.lookup_loc 'a/b'
    assert_not_nil b_loc

    loc = @context.lookup_loc '~foo'
    assert_equal nil, loc

    ['foo', '~', '7', ''].each do |mark|
      @context.mark mark, b_loc
      loc = @context.lookup_loc "~#{mark}"
      assert_equal [['', Root], ['a', NodeA], ['b', NodeB]], loc.stack

      @context.mark mark, nil
      loc = @context.lookup_loc "~#{mark}"
      assert_equal nil, loc
    end

    @context.mark '7', b_loc
    loc = @context.lookup_loc "7"
    assert_equal [['', Root], ['a', NodeA], ['b', NodeB]], loc.stack

    @context.mark '7', nil
    loc = @context.lookup_loc "7"
    assert_equal nil, loc
  end

  def test_cd
    assert_equal false, @context.cd("nonexistent")
    assert_equal [['', Root]], @context.loc.stack
    assert_equal true, @context.cd("a")
    assert_equal [['', Root], ['a', NodeA]], @context.loc.stack
  end
end
