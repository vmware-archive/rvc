raw_opts :execute, "Execute an esxcli command"

def execute *args
  path = args.shift
  o = lookup_single! path, [RVC::EsxcliMethod, VIM::EsxcliNamespace]
  case o
  when RVC::EsxcliMethod
    m = o
    parser = m.option_parser
    begin
      opts = parser.parse args
    rescue Trollop::CommandlineError
      err "error: #{$!.message}"
    rescue Trollop::HelpNeeded
      parser.educate
      return
    end
    begin
      pp m.ns.call(m.info.name, opts)
    rescue RbVmomi::Fault
      puts "cause: #{$!.faultCause}" if $!.faultCause
      $!.faultMessage.each { |x| puts x }
      $!.errMsg.each { |x| puts "error: #{x}" }
    end
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
