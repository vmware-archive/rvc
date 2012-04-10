# Copyright (c) 2011 VMware, Inc.  All Rights Reserved.
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

require 'rvc/option_parser'

module RVC

class Command
  attr_reader :ns, :name, :summary, :parser
  attr_accessor :completor

  def initialize ns, name, summary, parser
    @ns = ns
    @name = name
    @summary = summary
    @parser = parser
    @completor = nil
  end

  def inspect
    "#<RVC::Command:#{name}>"
  end

  def invoke *args
    @ns.slate.send @name, *args
  end

  def complete word, args
    if @completor
      candidates = @completor.call word, args
      prefix_regex = /^#{Regexp.escape word}/
      candidates.select { |x,a| x =~ prefix_regex }
    else
      return @ns.shell.completion.fs_candidates(word) +
             long_option_candidates(word)
    end
  end

  def long_option_candidates word
    return [] unless parser.is_a? RVC::OptionParser
    prefix_regex = /^#{Regexp.escape(word)}/
    parser.specs.map { |k,v| "--#{v[:long]}" }.
                 grep(prefix_regex).sort.
                 map { |x| [x, ' '] }
  end
end

end
