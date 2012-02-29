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

require 'rvc/util'
require 'rvc/field'
require 'rvc/inventory'
require 'rvc/operation'

module RVC

class Namespace
  attr_reader :name, :shell, :slate, :operations

  def initialize name, shell
    @name = name
    @shell = shell
    @slate = CmdSlate.new self
    @operations = {}
  end

  def load_code code, filename
    @slate.instance_eval code, filename
  end

  def method_missing sym, *args
    if @operations.member? sym
      @slate.send sym, *args
    else
      super
    end
  end
end

class RootNamespace
  attr_reader :shell

  def initialize shell
    @shell = shell
  end

  def method_missing sym, *args
    super unless args.empty?
    m = @shell.modules[sym.to_s]
    super unless m
    m
  end
end

# Execution environment for commands
class CmdSlate
  include RVC::Util

  def initialize ns
    @ns = ns
  end

  # Command definition functions

  def opts name, &b
    fail "operation name must be a symbol" unless name.is_a? Symbol

    if name.to_s =~ /[A-Z]/
      fail "Camel-casing is not allowed (#{name})"
    end

    parser = OptionParser.new name.to_s, @ns.shell.fs, &b

    parser.specs.each do |opt_name,spec|
      if opt_name.to_s =~ /[A-Z]/
        fail "Camel-casing is not allowed (#{name} option #{opt_name})"
      end
    end

    @ns.operations[name] = Operation.new @ns, name, parser
  end

  def raw_opts name, summary
    fail "operation name must be a symbol" unless name.is_a? Symbol

    if name.to_s =~ /[A-Z]/
      fail "Camel-casing is not allowed (#{name})"
    end

    parser = RawOptionParser.new name.to_s, summary

    @ns.operations[name] = Operation.new @ns, name, parser
  end

  def rvc_completor name, &b
    fail "operation name must be a symbol" unless name.is_a? Symbol
    op = @ns.operations[name] or fail "operation #{name} not defined"
    op.completor = b
  end

  def rvc_alias name, target=nil
    fail "operation name must be a symbol" unless name.is_a? Symbol
    target ||= name
    shell.aliases[target.to_s] = [@ns.name, name]
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
