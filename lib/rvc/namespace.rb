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

require 'rvc/command_slate'

module RVC

class Namespace
  attr_reader :name, :shell, :parent, :slate, :namespaces, :commands

  def initialize name, shell, parent
    @name = name
    @shell = shell
    @parent = parent
    @slate = CommandSlate.new self
    @namespaces = {}
    @commands = {}
  end

  def load_code code, filename
    @slate.instance_eval code, filename
  end

  def child_namespace name
    if ns = namespaces[name]
      return ns
    else
      namespaces[name] = Namespace.new(name, shell, self)
    end
  end

  def method_missing sym, *args
    if @commands.member? sym
      @slate.send sym, *args
    elsif @namespaces.member? sym and args.empty?
      @namespaces[sym]
    else
      super
    end
  end
end

end
