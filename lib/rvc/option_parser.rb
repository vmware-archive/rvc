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

require 'trollop'
require 'set'

module RVC

begin
  require 'chronic'
  HAVE_CHRONIC = true
rescue LoadError
  HAVE_CHRONIC = false
end

class OptionParser < Trollop::Parser
  attr_reader :applicable

  def initialize cmd, fs, &b
    @cmd = cmd
    @fs = fs
    @summary = nil
    @args = []
    @has_options = false
    @seen_not_required = false
    @seen_multi = false
    @applicable = Set.new
    super() do
      instance_eval &b
      opt :help, "Show this message", :short => 'h'
    end
  end

  def summary str
    @summary = str
    text str
  end

  def summary?
    @summary
  end

  def opt name, *a
    super
    spec = @specs[name]
    @applicable << spec[:lookup] if spec[:lookup]
    spec[:type] = :string if spec[:lookup] || spec[:lookup_parent]
    @has_options = true unless name == :help
  end

  def has_options?
    @has_options
  end

  def arg name, description, spec={}
    spec = {
      :description => description,
      :required => true,
      :default => nil,
      :multi => false,
    }.merge spec
    spec[:default] = [] if spec[:multi] and spec[:default].nil?
    fail "Multi argument must be the last one" if @seen_multi
    fail "Can't have required argument after optional ones" if spec[:required] and @seen_not_required
    fail "lookup and lookup_parent are mutually exclusive" if spec[:lookup] and spec[:lookup_parent]
    [:lookup, :lookup_parent].each do |sym|
      if spec[sym].is_a? Enumerable
        spec[sym].each { |x| @applicable << x }
      elsif spec[sym]
        @applicable << spec[sym]
      end
    end
    @args << [name,spec]
    description = "Path to a" if description == nil and spec[:lookup]
    description = "Child of a" if description == nil and spec[:lookup_parent]
    lookups = [spec[:lookup], spec[:lookup_parent]].flatten.compact
    text "  #{name}: " + [description, lookups*' or '].compact.join(' ')
  end

  def parse argv
    opts = super argv

    @specs.each do |name,spec|
      next unless klass = spec[:lookup] and path = opts[name]
      opts[name] = @fs.lookup_single! path, klass
    end

    argv = leftovers
    args = []
    @args.each do |name,spec|
      if spec[:multi]
        RVC::Util.err "missing argument '#{name}'" if spec[:required] and argv.empty?
        a = (argv.empty? ? spec[:default] : argv.dup)
        a = a.map { |x| postprocess_arg x, spec }.inject([], :+)
        RVC::Util.err "no matches for '#{name}'" if spec[:required] and a.empty?
        args << a
        argv.clear
      else
        x = argv.shift
        RVC::Util.err "missing argument '#{name}'" if spec[:required] and x.nil?
        x = spec[:default] if x.nil?
        a = x.nil? ? [] : postprocess_arg(x, spec)
        RVC::Util.err "more than one match for #{name}" if a.size > 1
        RVC::Util.err "no match for '#{name}'" if spec[:required] and a.empty?
        args << a.first
      end
    end
    RVC::Util.err "too many arguments" unless argv.empty?
    return args, opts
  end

  def parse_date_parameter param, arg
    if RVC::HAVE_CHRONIC
      Chronic.parse(param)
    else
      Time.parse param
    end
  rescue
    raise ::Trollop::CommandlineError, "option '#{arg}' needs a time"
  end

  def postprocess_arg x, spec
    if spec[:lookup]
      @fs.lookup!(x, spec[:lookup]).
        tap { |a| RVC::Util.err "no matches for #{x.inspect}" if a.empty? }
    elsif spec[:lookup_parent]
      @fs.lookup!(File.dirname(x), spec[:lookup_parent]).
        map { |y| [y, File.basename(x)] }.
        tap { |a| RVC::Util.err "no matches for #{File.dirname(x).inspect}" if a.empty? }
    else
      [x]
    end
  end

  def educate
    arg_texts = @args.map do |name,spec|
      text = name
      text = "[#{text}]" if not spec[:required]
      text = "#{text}..." if spec[:multi]
      text
    end
    arg_texts.unshift "[opts]" if has_options?
    puts "usage: #{@cmd} #{arg_texts*' '}"
    super
  end
end

class RawOptionParser
  attr_reader :applicable

  def initialize cmd
    @cmd = cmd
    @applicable = []
  end

  def parse args
    [args, {}]
  end

  def has_options?
    false
  end

  def educate
    # XXX
  end
end

end
