require 'test/unit'
require 'rvc'

class CompletionTest < Test::Unit::TestCase
  def setup
    session = RVC::MemorySession.new
    @shell = RVC::Shell.new(session)
    @shell.reload_modules false
  end

  def teardown
    @shell = nil
  end

  def test_cmd_candidates
    assert_equal [['basic.mkdir', ' ']], @shell.completion.cmd_candidates('basic.mkdi')
    assert_equal [['quit', ' ']], @shell.completion.cmd_candidates('qui')
  end
end
