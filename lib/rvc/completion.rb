module RVC
module Completion
  Completor = lambda do |word|
    Readline.completion_append_character = nil
    return unless word

    candidates = if Readline.respond_to? :line_buffer
      if Readline.line_buffer[' ']
        child_candidates(word)
      else
        cmd_candidates(word)
      end
    else
      child_candidates(word) + cmd_candidates(word)
    end

    candidates += mark_candidates(word)
        
    if candidates.length == 1 && candidates[0][-1..-1] != '/'
      Readline.completion_append_character = ' '
    end
    candidates
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
    cur.child_types.
      select { |k,v| k =~ /^#{Regexp.escape(last)}/ }.
      map { |k,v| v.folder? ? "#{k}/" : k }.
      map { |x| (els+[x])*'/' }
  end

  def self.mark_candidates word
    return [] unless word.empty? || word[0..0] == '~'
    prefix_regex = /^#{Regexp.escape(word[1..-1] || '')}/
    $context.marks.keys.sort.grep(prefix_regex).map { |x| "~#{x}" }
  end
end
end
