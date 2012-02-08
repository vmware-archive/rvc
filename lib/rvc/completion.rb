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
    begin
      line = Readline.line_buffer if Readline.respond_to? :line_buffer
      append_char, candidates = RVC::Completion.complete word, line
      Readline.completion_append_character = append_char
      candidates
    rescue RVC::Util::UserError
      puts
      puts $!.message
      Readline.refresh_line
    end
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
    line ||= ''
    first_whitespace_index = line.index(' ')

    if Readline.respond_to? :point
      do_complete_cmd = !first_whitespace_index || first_whitespace_index >= Readline.point
      do_complete_args = !do_complete_cmd
    else
      do_complete_cmd = true
      do_complete_args = true
    end

    candidates = []

    if do_complete_cmd
      candidates.concat cmd_candidates(word)
    end

    if do_complete_args
      mod, cmd, args = Shell.parse_input line
      if mod and mod.completor_for cmd
        candidates.concat RVC::complete_for_cmd(line, word)
      else
        candidates.concat(fs_candidates(word) +
                          long_option_candidates(mod, cmd, word))
      end
    end

    if candidates.size == 1
      append_char = candidates[0][1]
    else
      append_char = '?' # should never be displayed
    end

    return append_char, candidates.map(&:first)
  end

  def self.fs_candidates word
    child_candidates(word) + mark_candidates(word)
  end

  def self.cmd_candidates word
    ret = []
    prefix_regex = /^#{Regexp.escape(word)}/
    MODULES.each do |name,m|
      m.commands.each { |s| ret << "#{name}.#{s}" }
    end
    ret.concat ALIASES.keys
    ret.grep(prefix_regex).sort.
        map { |x| [x, ' '] }
  end

  def self.long_option_candidates mod, cmd, word
    return [] unless mod and cmd
    parser = mod.opts_for cmd
    return [] unless parser.is_a? RVC::OptionParser
    prefix_regex = /^#{Regexp.escape(word)}/
    parser.specs.map { |k,v| "--#{v[:long]}" }.
                 grep(prefix_regex).sort.
                 map { |x| [x, ' '] }
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
      map { |x| x.gsub ' ', '\\ ' }.
      map { |x| [x, '/'] }
  end

  def self.mark_candidates word
    return [] unless word.empty? || word[0..0] == '~'
    prefix_regex = /^#{Regexp.escape(word[1..-1] || '')}/
    $shell.session.marks.grep(prefix_regex).sort.
                         map { |x| ["~#{x}", '/'] }
  end
end
end
