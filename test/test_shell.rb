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
    @shell = RVC::Shell.new
    @shell.cmds = RVC::Namespace.new 'root', @shell, nil
    @shell.cmds.child_namespace(:foo).load_code FOO_MODULE, 'inline'
    @shell.cmds.child_namespace(:foo).child_namespace(:bar).load_code FOO_BAR_MODULE, 'inline'
  end

  def teardown
    @shell = nil
  end

  def test_parse_input
    cmdpath, args = RVC::Shell.parse_input 'module.cmd --longarg -s vm1 vm2 "spacy vm"'
    assert_equal [:module, :cmd], cmdpath
    assert_equal ['--longarg', '-s', 'vm1', 'vm2', 'spacy vm'], args

    cmdpath, args = RVC::Shell.parse_input 'module.cmd --longarg -s vm1 vm2 "spacy vm'
    assert_equal [:module, :cmd], cmdpath
    assert_equal ['--longarg', '-s', 'vm1', 'vm2', 'spacy vm'], args
  end

  def test_lookup_cmd
    ns = @shell.cmds.lookup [], RVC::Namespace
    assert_equal @shell.cmds, ns

    ret = @shell.cmds.lookup [], RVC::Command
    assert_equal nil, ret

    cmd = @shell.cmds.lookup [:foo, :foo]
    assert_equal @shell.cmds.foo.commands[:foo], cmd

    ret = @shell.cmds.lookup [:foo, :foo], RVC::Namespace
    assert_equal nil, ret

    cmd = @shell.cmds.lookup [:foo]
    assert_equal @shell.cmds.foo.commands[:foo], cmd

    ns = @shell.cmds.lookup [:foo], RVC::Namespace
    assert_equal @shell.cmds.foo, ns

    cmd = @shell.cmds.lookup [:f]
    assert_equal @shell.cmds.foo.commands[:foo], cmd

    ns = @shell.cmds.lookup [:foo, :bar], RVC::Namespace
    assert_equal @shell.cmds.foo.bar, ns

    cmd = @shell.cmds.lookup [:foo, :bar, :bar]
    assert_equal @shell.cmds.foo.bar.commands[:bar], cmd

    cmd = @shell.cmds.lookup [:bar]
    assert_equal @shell.cmds.foo.bar.commands[:bar], cmd

    ret = @shell.cmds.lookup [:nonexistent], RVC::Namespace
    assert_equal nil, ret

    ret = @shell.cmds.lookup [:nonexistent, :foo]
    assert_equal nil, ret
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
