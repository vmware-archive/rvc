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

require 'readline'
require 'rvc/ttl_cache'

if not defined? RbReadline
  begin
    require 'ffi'
    begin
      require 'rvc/readline-ffi'
    rescue Exception
      $stderr.puts "Error loading readline-ffi: #{$!.message}. Tab completion will be limited."
    end
  rescue LoadError
    $stderr.puts "Install the \"ffi\" gem for better tab completion."
  end
end

module RVC
module Completion
  Cache = TTLCache.new 10

  Completor = lambda do |word|
    return unless word
    line = Readline.line_buffer if Readline.respond_to? :line_buffer
    append_char, candidates = RVC::Completion.complete word, line
    Readline.completion_append_character = append_char
    candidates
  end

  def self.install
    if Readline.respond_to? :char_is_quoted=
      Readline.completer_word_break_characters = " \t\n\"'"
      Readline.completer_quote_characters = "\"\\"
      is_quoted = lambda { |str,i| i > 0 && str[i-1] == '\\' && !is_quoted[str,i-1] }
      Readline.char_is_quoted = is_quoted
    end

    Readline.completion_proc = Completor
  end

  def self.complete word, line
    candidates = if line
      if line[' ']
        child_candidates(word)
      else
        cmd_candidates(word)
      end
    else
      child_candidates(word) + cmd_candidates(word)
    end

    candidates += mark_candidates(word)

    if candidates.size == 1 and cmd_candidates(word).member?(candidates[0])
      append_char = ' '
    else
      append_char = '/'
    end

    return append_char, candidates
  end

  def self.cmd_candidates word
    ret = []
    prefix_regex = /^#{Regexp.escape(word)}/
    MODULES.each do |name,m|
      m.commands.each { |s| ret << "#{name}.#{s}" }
    end
    ret.concat ALIASES.keys
    ret.sort.select { |e| e.match(prefix_regex) }
  end

  # TODO convert to globbing
  def self.child_candidates word
    arcs, absolute, trailing_slash = Path.parse word
    last = trailing_slash ? '' : (arcs.pop || '')
    arcs.map! { |x| x.gsub '\\', '' }
    base = absolute ? $shell.fs.root : $shell.fs.cur
    cur = $shell.fs.traverse(base, arcs).first or return []
    arcs.unshift '' if absolute
    children = Cache[cur, :children] rescue []
    children.
      select { |k,v| k.gsub(' ', '\\ ') =~ /^#{Regexp.escape(last)}/ }.
      map { |k,v| (arcs+[k])*'/' }.
      map { |x| x.gsub ' ', '\\ ' }
  end

  def self.mark_candidates word
    return [] unless word.empty? || word[0..0] == '~'
    prefix_regex = /^#{Regexp.escape(word[1..-1] || '')}/
    $shell.fs.marks.keys.sort.grep(prefix_regex).map { |x| "~#{x}" }
  end
end
end
