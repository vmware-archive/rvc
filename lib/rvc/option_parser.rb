require 'trollop'

module RVC

class OptionParser < Trollop::Parser
  def summary str
    @summary = str
    text str
  end

  def summary?
    @summary
  end

  def usage str
    @usage = str
    text "Usage: #{str}"
  end

  def usage?
    @usage
  end
end

end
