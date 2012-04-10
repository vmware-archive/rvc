# Copyright (c) 2011-2012 VMware, Inc.  All Rights Reserved.
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

require 'rvc/command'
require 'rvc/option_parser'
require 'rvc/util'

module RVC

# Execution environment for command definitions
class CommandSlate
  include RVC::Util

  def initialize ns
    @ns = ns
  end

  # Command definition functions

  def opts name, &b
    fail "command name must be a symbol" unless name.is_a? Symbol

    if name.to_s =~ /[A-Z]/
      fail "Camel-casing is not allowed (#{name})"
    end

    parser = OptionParser.new name.to_s, @ns.shell.fs, &b
    summary = parser.summary?

    parser.specs.each do |opt_name,spec|
      if opt_name.to_s =~ /[A-Z]/
        fail "Camel-casing is not allowed (#{name} option #{opt_name})"
      end
    end

    @ns.commands[name] = Command.new @ns, name, summary, parser
  end

  def raw_opts name, summary
    fail "command name must be a symbol" unless name.is_a? Symbol

    if name.to_s =~ /[A-Z]/
      fail "Camel-casing is not allowed (#{name})"
    end

    parser = RawOptionParser.new name.to_s

    @ns.commands[name] = Command.new @ns, name, summary, parser
  end

  def rvc_completor name, &b
    fail "command name must be a symbol" unless name.is_a? Symbol
    cmd = @ns.commands[name] or fail "command #{name} not defined"
    cmd.completor = b
  end

  def rvc_alias name, target=nil
    fail "command name must be a symbol" unless name.is_a? Symbol
    target ||= name

    cmdpath = [name]
    cur = @ns
    while cur.parent
      cmdpath << cur.name
      cur = cur.parent
    end
    cmdpath.reverse!

    shell.cmds.aliases[target] = cmdpath
  end

  # Utility functions
  
  def shell
    @ns.shell
  end

  def lookup path
    shell.fs.lookup path
  end

  def lookup_single path
    shell.fs.lookup_single path
  end

  def lookup! path, types
    shell.fs.lookup! path, types
  end

  def lookup_single! path, types
    shell.fs.lookup_single! path, types
  end
end

end
