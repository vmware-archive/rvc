require 'test/unit'
require 'rvc'

class CompletionTest < Test::Unit::TestCase
  def setup
    session = RVC::MemorySession.new
    $shell = @shell = RVC::Shell.new(session)
    @shell.reload_modules false
  end

  def teardown
    $shell = @shell = nil
  end

  def test_cmd_candidates
    assert_equal [['basic.mkdir', ' ']], @shell.completion.cmd_candidates('basic.mkdi')
  end
end
