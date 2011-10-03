raw_opts :execute, "Execute an esxcli command"

def execute *args
  cli_info = VIM::VimCLIInfo.new(conn, 'ha-dynamic-type-manager-local-cli-cliinfo')
  path = args.shift
  o = lookup_single! path, [RVC::EsxcliMethod, VIM::EsxcliNamespace]
  case o
  when RVC::EsxcliMethod
    m = o
    parser = RVC::OptionParser.new m.info.name
    m.info.paramTypeInfo.each do |param|
      parser.opt param.name, param.name, trollop_type(param.type)
    end
    begin
      args, opts = parser.parse args
    rescue Trollop::HelpNeeded
      parser.educate
      return
    end
    pp m.ns.call(m.info.name, opts)
  when VIM::EsxcliNamespace
    unless o.commands.empty?
      puts "Available commands:"
      o.commands.each do |k,v|
        puts k
      end
      puts unless o.namespaces.empty?
    end
    unless o.namespaces.empty?
      puts "Available namespaces:"
      o.namespaces.each do |k,v|
        puts k
      end
    end
  end
end

rvc_alias :execute, :esxcli
rvc_alias :execute, :x

def trollop_type t
  if t[-2..-1] == '[]'
    multi = true
    t = t[0...-2]
  else
    multi = false
  end
  type = case t
  when 'string', 'boolean' then t.to_sym
  when 'long' then :int
  else fail "unexpected esxcli type #{t.inspect}"
  end
  { :type => type, multi => multi }
end
