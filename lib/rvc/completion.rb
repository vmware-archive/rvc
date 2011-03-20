require 'readline'
require 'rvc/ttl_cache'

unless Readline.respond_to? :line_buffer
  begin
    require 'readline_line_buffer'
  rescue LoadError
    $stderr.puts "Install the \"bond\" gem for better tab completion."
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

  def self.child_candidates word
    els, absolute, trailing_slash = Path.parse word
    last = trailing_slash ? '' : (els.pop || '')
    base_loc = absolute ? Location.new($context.root) : $context.loc
    found_loc = $context.traverse(base_loc, els) or return []
    cur = found_loc.obj
    els.unshift '' if absolute
    Cache[cur, :children].
      select { |k,v| k =~ /^#{Regexp.escape(last)}/ }.
      map { |k,v| (els+[k])*'/' }
  end

  def self.mark_candidates word
    return [] unless word.empty? || word[0..0] == '~'
    prefix_regex = /^#{Regexp.escape(word[1..-1] || '')}/
    $context.marks.keys.sort.grep(prefix_regex).map { |x| "~#{x}" }
  end
end
end
