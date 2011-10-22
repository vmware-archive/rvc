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
require 'shellwords'

module RVC

ALIASES = {}
MODULES = {}

class CmdModule
  include RVC::Util

  def initialize module_name
    @module_name = module_name
    @opts = {}
    @completors = {}
    super()
  end

  def commands
    @opts.keys
  end

  def opts cmd, &b
    @opts[cmd] = OptionParser.new cmd.to_s, &b
  end

  def raw_opts cmd, summary
    @opts[cmd] = RawOptionParser.new cmd.to_s, summary
  end

  def opts_for cmd
    @opts[cmd]
  end

  def rvc_completor cmd, &b
    @completors[cmd] = b
  end

  def completor_for cmd
    @completors[cmd]
  end

  def rvc_alias cmd, target=nil
    target ||= cmd
    RVC::ALIASES[target.to_s] = "#{@module_name}.#{cmd}"
  end
end

def self.complete_for_cmd line, word
  if line == nil
    return []
  end
  mod, cmd, args = Shell.parse_input line
  return [] unless mod != nil
  #XXX assumes you aren't going to have any positional arguments with spaces
  if(/ $/.match(line))
    argnum = args.size
  else
    argnum = args.size - 1
  end

  completor = mod.completor_for(cmd.to_sym)
  if completor == nil
    return []
  end

  candidates = completor.call(line, args, word, argnum)
  if candidates == nil
    []
  else
    prefix_regex = /^#{Regexp.escape word}/
    candidates.select { |x,a| x =~ prefix_regex }
  end
end

BULTIN_MODULE_PATH = [File.expand_path(File.join(File.dirname(__FILE__), 'modules')),
                      File.join(ENV['HOME'], ".rvc")]
ENV_MODULE_PATH = (ENV['RVC_MODULE_PATH'] || '').split ':'

def self.reload_modules verbose=true
  RVC::MODULES.clear
  RVC::ALIASES.clear
  RVC::MODULES['custom'] = CmdModule.new 'custom'
  module_path = (BULTIN_MODULE_PATH+ENV_MODULE_PATH).select { |d| File.directory?(d) }
  globs = module_path.map { |d| File.join(d, '*.rb') }
  Dir.glob(globs) do |f|
    module_name = File.basename(f)[0...-3]
    puts "loading #{module_name} from #{f}" if verbose
    begin
      code = File.read f
      unless RVC::MODULES.member? module_name
        m = CmdModule.new module_name
        CMD.define_singleton_method(module_name.to_sym) { m }
        RVC::MODULES[module_name] = m
      end
      RVC::MODULES[module_name].instance_eval code, f
    rescue
      puts "#{$!.class} while loading #{f}: #{$!.message}"
      $!.backtrace.each { |x| puts x }
    end
  end
end

end
