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

require 'rvc/modules'
require 'shellwords'

module RVC

class Shell
  attr_reader :fs, :completion, :session
  attr_reader :connections, :modules, :aliases, :cmds
  attr_accessor :debug

  class InvalidCommand < StandardError; end

  def initialize session
    @session = session
    @persist_ruby = false
    @fs = RVC::FS.new RVC::RootNode.new(self), session
    @ruby_evaluator = RVC::RubyEvaluator.new self
    @completion = RVC::Completion.new self
    @connections = {}
    @debug = false
    @modules = {}
    @aliases = {}
    @cmds = RVC::RootCmdModule.new self
  end

  def inspect
    "#<RVC::Shell:#{object_id}>"
  end

  def eval_input input
    if input == '//'
      @persist_ruby = !@persist_ruby
      return
    end

    if input[0..0] == '!'
      RVC::Util.system_fg input[1..-1]
      return
    end

    ruby = @persist_ruby
    if input =~ /^\//
      input = $'
      ruby = !ruby
    end

    begin
      if ruby
        eval_ruby input
      else
        eval_command input
      end
    rescue SystemExit, IOError
      raise
    rescue RVC::Util::UserError, RuntimeError, RbVmomi::Fault, Trollop::CommandlineError
      if ruby or debug
        puts "#{$!.class}: #{$!.message}"
        puts $!.backtrace * "\n"
      else
        case $!
        when RbVmomi::Fault, RVC::Util::UserError
          puts $!.message
        else
          puts "#{$!.class}: #{$!.message}"
        end
      end
    rescue Exception
      puts "#{$!.class}: #{$!.message}"
      puts $!.backtrace * "\n"
    ensure
      $stdout.flush
    end
  end

  def self.parse_input input
    begin
      cmd, *args = Shellwords.shellwords(input)
    rescue ArgumentError # unmatched double quote
      cmd, *args = Shellwords.shellwords(input + '"')
    end
    return nil unless cmd
    cmd = cmd.split '.'
    [cmd, args]
  end

  def lookup_cmd cmd
    if cmd.length == 2
      ns_name, op_name = cmd
      ns = modules[ns_name] or raise InvalidCommand
      ns.operations[op_name.to_sym] or raise InvalidCommand
    elsif cmd.length == 1 and aliases.member? cmd[0]
      lookup_cmd aliases[cmd[0]]
    elsif cmd.length == 1
      ns_name, = cmd
      modules[ns_name] or raise InvalidCommand
    else
      raise InvalidCommand
    end
  end

  def eval_command input
    cmd, args = Shell.parse_input input

    begin
      op = lookup_cmd cmd
    rescue InvalidCommand
      RVC::Util.err "invalid command"
    end

    begin
      args, opts = op.parser.parse args
    rescue Trollop::HelpNeeded
      op.parser.educate
      return
    end

    if op.parser.has_options?
      op.invoke *(args + [opts])
    else
      op.invoke *args
    end
  end

  def eval_ruby input, file="<input>"
    result = @ruby_evaluator.do_eval input, file
    if $interactive
      if input =~ /\#$/
        if result.is_a? Class
          introspect_class result
        else
          introspect_object result
        end
      else
        pp result
      end
    end
  end

  def prompt
    if false
      "#{@fs.display_path}#{$terminal.color(@persist_ruby ? '~' : '>', :yellow)} "
    else
      "#{@fs.display_path}#{@persist_ruby ? '~' : '>'} "
    end
  end

  def introspect_object obj
    case obj
    when RbVmomi::VIM::DataObject, RbVmomi::VIM::ManagedObject
      introspect_class obj.class
    when Array
      klasses = obj.map(&:class).uniq
      if klasses.size == 0
        puts "Array"
      elsif klasses.size == 1
        $stdout.write "Array of "
        introspect_class klasses[0]
      else
        counts = Hash.new 0
        obj.each { |o| counts[o.class] += 1 }
        puts "Array of:"
        counts.each { |k,c| puts "  #{k}: #{c}" }
        puts
        $stdout.write "Common ancestor: "
        introspect_class klasses.map(&:ancestors).inject(&:&)[0]
      end
    else
      introspect_class obj.class
    end
  end

  def introspect_class klass
    q = lambda { |x| x =~ /^xsd:/ ? $' : x }
    if klass < RbVmomi::VIM::DataObject
      puts "Data Object #{klass}"
      klass.full_props_desc.each do |desc|
        puts " #{desc['name']}: #{q[desc['wsdl_type']]}#{desc['is-array'] ? '[]' : ''}"
      end
    elsif klass < RbVmomi::VIM::ManagedObject
      puts "Managed Object #{klass}"
      puts
      puts "Properties:"
      klass.full_props_desc.each do |desc|
        puts " #{desc['name']}: #{q[desc['wsdl_type']]}#{desc['is-array'] ? '[]' : ''}"
      end
      puts
      puts "Methods:"
      klass.full_methods_desc.sort_by(&:first).each do |name,desc|
        params = desc['params']
        puts " #{name}(#{params.map { |x| "#{x['name']} : #{q[x['wsdl_type'] || 'void']}#{x['is-array'] ? '[]' : ''}" } * ', '}) : #{q[desc['result']['wsdl_type'] || 'void']}"
      end
    else
      puts "#{klass} < #{klass.superclass}"
      puts
      methods_by_class = klass.instance_methods.map { |x| klass.instance_method(x) }.group_by { |m| m.owner }
      klass.ancestors.each do |ancestor|
        break if ancestor == Object
        if ancestor == klass
          puts "Methods:"
        else
          puts "Methods from #{ancestor}:"
        end
        methods_by_class[ancestor].sort_by { |m| m.name }.each do |m|
          if m.respond_to? :parameters
            puts " #{m.name}(#{m.parameters.map { |mode,name| "#{name}#{mode==:opt ? '?' : ''}" } * ', '})"
          else
            puts " #{m.name}"
          end
        end
      end
    end
  end

  def delete_numeric_marks
    @session.marks.grep(/^\d+$/).each { |x| @session.set_mark x, nil }
  end

  BULTIN_MODULE_PATH = [File.expand_path(File.join(File.dirname(__FILE__), 'modules')),
                        File.join(ENV['HOME'], ".rvc")]
  ENV_MODULE_PATH = (ENV['RVC_MODULE_PATH'] || '').split ':'

  def reload_modules verbose=true
    modules.clear
    aliases.clear
    module_path = (BULTIN_MODULE_PATH+ENV_MODULE_PATH).select { |d| File.directory?(d) }
    globs = module_path.map { |d| File.join(d, '*.rb') }
    Dir.glob(globs) do |f|
      module_name = File.basename(f)[0...-3]
      puts "loading #{module_name} from #{f}" if verbose
      begin
        code = File.read f
        unless modules.member? module_name
          m = CmdModule.new module_name, self
          modules[module_name] = m
        end
        modules[module_name].load_code code, f
      rescue
        puts "#{$!.class} while loading #{f}: #{$!.message}"
        $!.backtrace.each { |x| puts x }
      end
    end
  end
end

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

  def method_missing sym, *a
    str = sym.to_s
    if a.empty?
      if @shell.modules.member? str
        @shell.modules[str]
      elsif str =~ /_?([\w\d]+)(!?)/ && objs = @shell.session.get_mark($1)
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
