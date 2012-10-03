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

class Completion
  def initialize shell
    @shell = shell
    @cache = TTLCache.new 10
  end

  # Halt infinite loop when printing exceptions
  def inspect
    ""
  end

  def install
    if Readline.respond_to? :char_is_quoted=
      Readline.completer_word_break_characters = " \t\n\"'"
      Readline.completer_quote_characters = "\"\\"
      is_quoted = lambda { |str,i| i > 0 && str[i-1] == '\\' && !is_quoted[str,i-1] }
      Readline.char_is_quoted = is_quoted
    end

    Readline.completion_proc = lambda { |word| completor(word) }
  end

  def completor word
    return unless word
    begin
      line = Readline.line_buffer if Readline.respond_to? :line_buffer
      point = Readline.point if Readline.respond_to? :point
      append_char, candidates = complete word, line, point
      Readline.completion_append_character = append_char
      candidates
    rescue RVC::Util::UserError
      puts
      puts $!.message
      Readline.refresh_line
    rescue
      puts
      puts "#{$!.class}: #{$!.message}"
      $!.backtrace.each do |x|
        puts x
      end
      Readline.refresh_line
    end
  end

  def complete word, line, point
    candidates = []

    if line and point
      # Full completion capabilities
      line = line[0...point]
      first_whitespace_index = line.index(' ')

      if !first_whitespace_index
        # Command
        candidates.concat cmd_candidates(word)
      else
        # Arguments
        begin
          cmdpath, args = Shell.parse_input line
        rescue ArgumentError
          # Unmatched double quote
          cmdpath, args = Shell.parse_input(line+'"')
        end

        if cmd = @shell.cmds.lookup(cmdpath)
          args << word if word == ''
          candidates.concat cmd.complete(word, args)
        else
          candidates.concat fs_candidates(word)
        end
      end
    else
      # Limited completion
      candidates.concat cmd_candidates(word)
      candidates.concat fs_candidates(word)
    end

    if candidates.size == 1
      append_char = candidates[0][1]
    else
      append_char = '?' # should never be displayed
    end

    return append_char, candidates.map(&:first)
  end

  def fs_candidates word
    child_candidates(word) + mark_candidates(word)
  end

  def cmd_candidates word
    cmdpath = word.split '.'
    cmdpath << '' if cmdpath.empty? or word[-1..-1] == '.'
    prefix_regex = /^#{Regexp.escape(cmdpath[-1])}/

    ns = @shell.cmds.lookup(cmdpath[0...-1].map(&:to_sym), RVC::Namespace)
    return [] unless ns

    cmdpath_prefix = cmdpath[0...-1].join('.')
    cmdpath_prefix << '.' unless cmdpath_prefix.empty?

    ret = []

    ns.commands.each do |cmd_name,cmd|
      ret << ["#{cmdpath_prefix}#{cmd_name}", ' '] if cmd_name.to_s =~ prefix_regex
    end

    ns.namespaces.each do |ns_name,ns|
      ret << ["#{cmdpath_prefix}#{ns_name}.", ''] if ns_name.to_s =~ prefix_regex
    end

    # Aliases
    if ns == @shell.cmds then
      ret.concat @shell.cmds.aliases.keys.map(&:to_s).grep(prefix_regex).map { |x| [x, ' '] }
    end

    ret.sort_by! { |a,b| a }
    ret
  end

  # TODO convert to globbing
  def child_candidates word
    arcs, absolute, trailing_slash = Path.parse word
    last = trailing_slash ? '' : (arcs.pop || '')
    arcs.map! { |x| x.gsub '\\', '' }
    base = absolute ? @shell.fs.root : @shell.fs.cur
    cur = @shell.fs.traverse(base, arcs).first or return []
    arcs.unshift '' if absolute
    children = @cache[cur, :rvc_children] rescue []
    children.
      select { |k,v| k.gsub(' ', '\\ ') =~ /^#{Regexp.escape(last)}/ }.
      map { |k,v| (arcs+[k])*'/' }.
      map { |x| x.gsub ' ', '\\ ' }.
      map { |x| [x, '/'] }
  end

  def mark_candidates word
    return [] unless word.empty? || word[0..0] == '~'
    prefix_regex = /^#{Regexp.escape(word[1..-1] || '')}/
    @shell.fs.marks.keys.grep(prefix_regex).sort.
                         map { |x| ["~#{x}", '/'] }
  end
end
end
