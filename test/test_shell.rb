require 'test_helper'

FOO_MODULE = <<-EOS
opts :foo do
  summary "Foo it"
end

def foo
end

rvc_alias :foo
rvc_alias :foo, :f
EOS

FOO_BAR_MODULE = <<-EOS
opts :bar do
  summary "Bar it"
end

def bar
end

rvc_alias :bar
EOS

def redirect
  orig = $stdout
  begin
    $stdout = File.new('/dev/null', 'w')
    yield
  ensure
    $stdout = orig
  end
end

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

  def test_ruby_mode
    $ruby_mod_result = 0

    redirect do
      @shell.eval_input '/$ruby_mode_result = 1'
    end
    assert_equal 1, $ruby_mode_result

    redirect do
      @shell.eval_input '//'
      @shell.eval_input '$ruby_mode_result = 2'
    end
    assert_equal 2, $ruby_mode_result

    redirect do
      @shell.cmds.foo.foo
    end

    redirect do
      @shell.eval_input '/nonexistent_command'
    end

    redirect do
      @shell.eval_input '//'
      @shell.eval_input '/$ruby_mode_result = 3'
    end
    assert_equal 3, $ruby_mode_result
  end

  def test_eval_command
    assert_raise RVC::Util::UserError do
      @shell.eval_command ''
    end

    assert_raise RVC::Util::UserError do
      @shell.eval_command '.'
    end

    assert_raise RVC::Util::UserError do
      @shell.eval_command '?'
    end
  end
end
