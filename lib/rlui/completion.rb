module RLUI
module Completion
  Completor = lambda do |word|
    return unless word

    els, absolute, trailing_slash = $context.parse_path word
    last = trailing_slash ? '' : (els.pop || '')
    base = absolute ? $context.root : $context.cur
    cur = $context.traverse(base, els) or return
    child_map = case cur
    when VIM::Folder
      Hash[cur.children.map { |x| [x.name, x] }]
    when VIM::Datacenter
      { 'vm' => cur.vmFolder, 'datastore' => cur.datastoreFolder,
        'network' => cur.networkFolder, 'host' => cur.hostFolder }
    else
      []
    end

    child_candidates = child_map.select { |k,v| k =~ /^#{Regexp.escape(last)}/ }.map do |k,v|
      case v
      when VIM::Folder then "#{k}/"
      else "#{k} "
      end
    end

    child_candidates.map! { |x| (els+[x])*'/' }

    cmd_candidates = []
    prefix_regex = /^#{Regexp.escape(word)}/
    MODULES.each do |name,m|
      m.commands.each { |s| cmd_candidates << "#{name}.#{s}" }
    end
    cmd_candidates.concat ALIASES.keys
    cmd_candidates.sort!.select! { |e| e.match(prefix_regex) }

    cmd_candidates + child_candidates
  end
end
end
