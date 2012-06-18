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

module RVC

class RubyEvaluator
  include RVC::Util

  def initialize shell
    @binding = toplevel
    @shell = shell
  end

  def toplevel
    binding
  end

  def do_eval input, file
    begin
      eval input, @binding, file
    rescue Exception => e
      bt = e.backtrace
      bt = bt.reverse.drop_while { |x| !(x =~ /toplevel/) }.reverse
      bt[-1].gsub! ':in `toplevel\'', '' if bt[-1]
      e.set_backtrace bt
      raise
    end
  end

  def this
    @shell.fs.cur
  end

  def dc
    @shell.fs.lookup("~").first
  end

  def conn
    @shell.fs.lookup("~@").first
  end

  def rvc_exec command
    @shell.eval_command command
  end

  def method_missing sym, *a
    if a.empty?
      if @shell.cmds.namespaces.member? sym
        @shell.cmds.namespaces[sym]
      elsif sym.to_s =~ /_?([\w\d]+)(!?)/ && objs = @shell.fs.marks[$1]
        if $2 == '!'
          objs
        else
          objs.first
        end
      else
        super
      end
    else
      super
    end
  end
end

end
