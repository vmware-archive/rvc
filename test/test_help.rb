require 'test_helper'

class HelpTest < Test::Unit::TestCase
  def setup
    @shell = RVC::Shell.new
    @shell.reload_modules false
  end

  def teardown
    @shell = nil
  end

  def redirect
    orig = $stdout
    begin
      $stdout = File.new('/dev/null', 'w')
      yield
    ensure
      $stdout = orig
    end
  end

  def test_all
    redirect do
      @shell.cmds.basic.help nil
    end
  end

  def test_ns
    redirect do
      @shell.cmds.basic.help 'basic'
    end
  end

  def test_cmd
    redirect do
      @shell.cmds.basic.help 'basic.info'
    end
  end

  def test_alias
    redirect do
      @shell.cmds.basic.help 'i'
    end
  end
end
