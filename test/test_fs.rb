require 'test_helper'
require 'inventory_fixtures'

class FSTest < Test::Unit::TestCase
  NodeDaa = FixtureNode.new 'Daa'
  NodeDab = FixtureNode.new 'Dab'
  NodeDabc = FixtureNode.new 'Dabc'
  NodeDac = FixtureNode.new 'Dac'
  NodeB = FixtureNode.new 'B'
  NodeC = FixtureNode.new 'C'
  NodeD = FixtureNode.new('D', 'daa' => NodeDaa, 'dab' => NodeDab,
                               'dabc' => NodeDabc, 'dac' => NodeDac)
  NodeA = FixtureNode.new('A', 'b' => NodeB, 'c' => NodeC)
  Root = FixtureNode.new('ROOT', 'a' => NodeA, 'd' => NodeD)

  Root.rvc_link nil, ''

  def setup
    @context = RVC::FS.new Root
    @shell = RVC::Shell.new
    @shell.instance_variable_set :@fs, @context
  end

  def teardown
    @context = nil
    @shell = nil
  end

  def test_new
    assert_equal Root, @context.cur
    assert_equal "", @context.display_path
    assert_equal 0, @shell.fs.marks.size
    assert_equal [['', Root]], @context.cur.rvc_path
  end

  def test_lookup_simple
    assert_equal [], @context.lookup('nonexistent')
    assert_equal [Root], @context.lookup('.')
    assert_equal [Root], @context.lookup('..')
    assert_equal [Root], @context.lookup('...')
    assert_equal [NodeA], @context.lookup('a')
    assert_equal [NodeB], @context.lookup('a/b')
    assert_equal [NodeC], @context.lookup('a/b/../c')
    assert_equal [NodeC], @context.lookup('a/b/.../c')
  end

  def test_lookup_nonexistent
    objs = @context.lookup 'nonexistent'
    assert_equal [], objs
  end

  def test_lookup_simple_path
    %w(a /a ./a ./a/.).each do |path|
      obj = @context.lookup(path)[0]
      assert_equal NodeA, obj
      assert_equal [['', Root], ['a', NodeA]], obj.rvc_path
    end

    %w(a/b /a/b ./a/b /a/b/.).each do |path|
      obj = @context.lookup(path)[0]
      assert_equal NodeB, obj
      assert_equal [['', Root], ['a', NodeA], ['b', NodeB]], obj.rvc_path
    end
  end

  def test_lookup_parent
    obj = @context.lookup('..')[0]
    assert_equal [['', Root]], obj.rvc_path

    obj = @context.lookup('a/..')[0]
    assert_equal [['', Root]], obj.rvc_path

    obj = @context.lookup('a/b/..')[0]
    assert_equal [['', Root], ['a', NodeA]], obj.rvc_path
  end

=begin
  def test_lookup_loc_realparent
    obj = @context.lookup('...')[0]
    assert_equal [['', Root]], obj.rvc_path

    obj = @context.lookup('a/...')[0]
    assert_equal [['', Root], ['a', NodeA], ['...', Root]], obj.rvc_path

    obj = @context.lookup('a/b/...')[0]
    assert_equal [['', Root], ['a', NodeA], ['b', NodeB], ['...', NodeA]], obj.rvc_path
  end
=end

  def test_lookup_mark
    b_obj = @context.lookup('a/b')[0]
    assert_not_nil b_obj

    obj = @context.lookup('~foo')[0]
    assert_equal nil, obj

    ['foo', '~', '7', ''].each do |mark|
      @shell.fs.marks[mark] = [b_obj]
      obj = @context.lookup("~#{mark}")[0]
      assert_equal [['', Root], ['a', NodeA], ['b', NodeB]], obj.rvc_path

      @shell.fs.marks[mark] = []
      obj = @context.lookup("~#{mark}")[0]
      assert_equal nil, obj
    end

    @shell.fs.marks['7'] = [b_obj]
    obj = @context.lookup("7")[0]
    assert_equal [['', Root], ['a', NodeA], ['b', NodeB]], obj.rvc_path

    @shell.fs.marks['7'] = []
    obj = @context.lookup("7")[0]
    assert_equal nil, obj
  end

  def test_cd
    assert_equal [['', Root]], @context.cur.rvc_path
    @context.cd(@context.lookup("a")[0])
    assert_equal [['', Root], ['a', NodeA]], @context.cur.rvc_path
  end

  def test_regex
    daa = [['', Root], ['d', NodeD], ['daa', NodeDaa]]
    dab = [['', Root], ['d', NodeD], ['dab', NodeDab]]
    dabc = [['', Root], ['d', NodeD], ['dabc', NodeDabc]]
    dac = [['', Root], ['d', NodeD], ['dac', NodeDac]]
    objs = @context.lookup '/d/%^daa'
    assert_equal [daa], objs.map(&:rvc_path)
    objs = @context.lookup '/d/%^daa.*'
    assert_equal [daa], objs.map(&:rvc_path)
    objs = @context.lookup '/d/%^da.*c'
    assert_equal [dabc, dac], objs.map(&:rvc_path)
  end

  def test_glob
    daa = [['', Root], ['d', NodeD], ['daa', NodeDaa]]
    dab = [['', Root], ['d', NodeD], ['dab', NodeDab]]
    dabc = [['', Root], ['d', NodeD], ['dabc', NodeDabc]]
    dac = [['', Root], ['d', NodeD], ['dac', NodeDac]]
    objs = @context.lookup '/d/*daa*'
    assert_equal [daa], objs.map(&:rvc_path)
    objs = @context.lookup '/d/d*a'
    assert_equal [daa], objs.map(&:rvc_path)
    objs = @context.lookup '/d/da*c'
    assert_equal [dabc, dac], objs.map(&:rvc_path)
  end
end
