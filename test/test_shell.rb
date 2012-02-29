require 'test/unit'
require 'rvc'

FOO_MODULE = <<-EOS
opts :foo do
  summary "Foo it"
end

rvc_alias :foo
rvc_alias :foo, :f
EOS

FOO_BAR_MODULE = <<-EOS
opts :bar do
  summary "Bar it"
end

rvc_alias :bar
EOS

class ShellTest < Test::Unit::TestCase
  def setup
    session = RVC::MemorySession.new
    @shell = RVC::Shell.new(session)
    @shell.cmds = RVC::Namespace.new 'root', @shell, nil
    @shell.cmds.child_namespace(:foo).load_code FOO_MODULE, 'inline'
    @shell.cmds.child_namespace(:foo).child_namespace(:bar).load_code FOO_BAR_MODULE, 'inline'
  end

  def teardown
    @shell = nil
  end

  def test_parse_input
    cmdpath, args = RVC::Shell.parse_input "module.cmd --longarg -s vm1 vm2"
    assert_equal [:module, :cmd], cmdpath
    assert_equal ['--longarg', '-s', 'vm1', 'vm2'], args
  end

  def test_lookup_cmd
    ns = @shell.lookup_cmd []
    assert_equal @shell.cmds, ns

    cmd = @shell.lookup_cmd [:foo, :foo]
    assert_equal @shell.cmds.foo.commands[:foo], cmd

    cmd = @shell.lookup_cmd [:foo]
    assert_equal @shell.cmds.foo.commands[:foo], cmd

    cmd = @shell.lookup_cmd [:f]
    assert_equal @shell.cmds.foo.commands[:foo], cmd

    ns = @shell.lookup_cmd [:foo, :bar]
    assert_equal @shell.cmds.foo.bar, ns

    cmd = @shell.lookup_cmd [:foo, :bar, :bar]
    assert_equal @shell.cmds.foo.bar.commands[:bar], cmd

    cmd = @shell.lookup_cmd [:bar]
    assert_equal @shell.cmds.foo.bar.commands[:bar], cmd

    assert_raise RVC::Shell::InvalidCommand do
      @shell.lookup_cmd [:nonexistent]
    end

    assert_raise RVC::Shell::InvalidCommand do
      @shell.lookup_cmd [:nonexistent, :foo]
    end
  end
end
