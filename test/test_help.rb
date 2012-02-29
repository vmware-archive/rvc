require 'test/unit'
require 'rvc'

class ShellTest < Test::Unit::TestCase
  def setup
    session = RVC::MemorySession.new
    @shell = RVC::Shell.new(session)
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
      @shell.namespaces[:basic].help nil
    end
  end

  def test_ns
    redirect do
      @shell.namespaces[:basic].help 'basic'
    end
  end

  def test_cmd
    redirect do
      @shell.namespaces[:basic].help 'basic.info'
    end
  end

  def test_alias
    redirect do
      @shell.namespaces[:basic].help 'i'
    end
  end

  def test_obj
    redirect do
      @shell.namespaces[:basic].help '/'
    end
  end
end
