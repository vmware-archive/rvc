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

module RVC

class OptionParser < Trollop::Parser
  attr_reader :applicable

  def initialize cmd, &b
    @cmd = cmd
    @summary = nil
    @args = []
    @has_options = false
    @seen_not_required = false
    @seen_multi = false
    @applicable = Set.new
    super &b
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
    @applicable << @specs[name][:lookup] if @specs[name][:lookup]
    @has_options = true unless name == :help
  end

  def has_options?
    @has_options
  end

  def arg name, description, opts={}
    opts = {
      :required => true,
      :default => nil,
      :multi => false,
    }.merge opts
    opts[:default] = [] if opts[:multi] and opts[:default].nil?
    fail "Multi argument must be the last one" if @seen_multi
    fail "Can't have required argument after optional ones" if opts[:required] and @seen_not_required
    @applicable << opts[:lookup] if opts[:lookup]
    @args << [name, description, opts[:required], opts[:default], opts[:multi], opts[:lookup]]
    text "  #{name}: " + [description, opts[:lookup]].compact.join(' ')
  end

  def parse argv
    opts = super argv

    @specs.each do |name,spec|
      next unless klass = spec[:lookup] and path = opts[name]
      opts[name] = lookup! path, klass
    end

    argv = leftovers
    args = []
    @args.each do |name,desc,required,default,multi,lookup_klass|
      if multi
        err "missing argument '#{name}'" if required and argv.empty?
        a = (argv.empty? ? default : argv.dup)
        a.map! { |x| lookup! x, lookup_klass } if lookup_klass
        args << a
        argv.clear
      else
        x = argv.shift
        err "missing argument '#{name}'" if required and x.nil?
        x = default if x.nil?
        x = lookup! x, lookup_klass if lookup_klass
        args << x
      end
    end
    err "too many arguments" unless argv.empty?
    return args, opts
  end

  def educate
    arg_texts = @args.map do |name,desc,required,default,multi,lookup_klass|
      text = name
      text = "[#{text}]" if not required
      text = "#{text}..." if multi
      text
    end
    arg_texts.unshift "[opts]" if has_options?
    puts "usage: #{@cmd} #{arg_texts*' '}"
    super
  end
end

end
