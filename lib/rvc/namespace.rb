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
  attr_reader :name, :shell, :parent, :slate, :namespaces, :commands, :aliases

  def inspect
    "#<RVC::Namespace:#{name}>"
  end

  def initialize name, shell, parent
    @name = name
    @shell = shell
    @parent = parent
    @slate = CommandSlate.new self
    @namespaces = {}
    @commands = {}
    @aliases = {}
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

  def lookup cmdpath, accept=Command
    if cmdpath.empty?
      if accept == Command
        return nil
      elsif accept == Namespace
        return self
      end
    elsif cmdpath.length == 1 and accept == Command
      sym = cmdpath[0]
      if @aliases.member? sym
        @shell.cmds.lookup @aliases[sym], accept
      else
        @commands[sym]
      end
    else
      sym = cmdpath[0]
      child = @namespaces[sym]
      return nil if child == nil
      child.lookup cmdpath[1..-1], accept
    end
  end

  def [] sym
    @namespaces[sym]
  end

  def method_missing sym, *args
    if cmd = @commands[sym]
      cmd.invoke *args
    elsif args.empty? and x = self[sym]
      x
    else
      super
    end
  end

  def load_module_dir dir, verbose
    puts "loading module directory #{dir}" if verbose
    Dir.foreach(dir) do |f|
      path = File.join(dir, f)
      if f[0..0] == '.'
        next
      elsif File.directory? path
        ns_name = f.to_sym
        child_namespace(ns_name).load_module_dir(path, verbose)
      elsif f =~ /\.rb$/
        ns_name = f[0...-3].to_sym
        puts "loading #{ns_name} from #{path}" if verbose
        begin
          code = File.read path
          child_namespace(ns_name).load_code(code, path)
        rescue
          puts "#{$!.class} while loading #{f}: #{$!.message}"
          $!.backtrace.each { |x| puts x }
        end
      end
    end
  end
end

end
