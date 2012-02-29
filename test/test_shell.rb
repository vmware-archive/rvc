require 'test/unit'
require 'rvc'

BASIC_MODULE = <<-EOS
opts :info do
  summary "Display information about an object"
  arg :path, nil, :lookup => Object
end

rvc_alias :info
rvc_alias :info, :i
EOS

class ShellTest < Test::Unit::TestCase
  def setup
    session = RVC::MemorySession.new
    @shell = RVC::Shell.new(session)
    @shell.cmds = RVC::Namespace.new 'root', @shell
    @shell.cmds.child_namespace(:basic).load_code BASIC_MODULE, 'inline'
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

    cmd = @shell.lookup_cmd [:basic, :info]
    assert_equal @shell.cmds.basic.commands[:info], cmd

    cmd = @shell.lookup_cmd [:info]
    assert_equal @shell.cmds.basic.commands[:info], cmd

    cmd = @shell.lookup_cmd [:i]
    assert_equal @shell.cmds.basic.commands[:info], cmd

    ns = @shell.lookup_cmd [:basic]
    assert_equal @shell.cmds.basic, ns

    assert_raise RVC::Shell::InvalidCommand do
      @shell.lookup_cmd [:nonexistent]
    end

    assert_raise RVC::Shell::InvalidCommand do
      @shell.lookup_cmd [:nonexistent, :foo]
    end
  end
end
