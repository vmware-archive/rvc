module RLUI
module Completion
  Completor = lambda do |word|
    return unless word
    child_candidates(word) + cmd_candidates(word)
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
    els, absolute, trailing_slash = $context.parse_path word
    last = trailing_slash ? '' : (els.pop || '')
    base = absolute ? $context.root : $context.cur
    cur = $context.traverse(base, els) or return []
    cur.child_map.
      select { |k,v| k =~ /^#{Regexp.escape(last)}/ }.
      map { |k,v| v.is_a?(VIM::Folder) ? "#{k}/" : "#{k} " }.
      map { |x| (els+[x])*'/' }
  end
end
end
