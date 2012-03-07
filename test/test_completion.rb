require 'test_helper'

class CompletionTest < Test::Unit::TestCase
  def setup
    @shell = RVC::Shell.new
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
