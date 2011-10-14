raw_opts :execute, "Execute an esxcli command"

def execute *args
  path = args.shift
  o = lookup_single! path, [VIM::EsxcliCommand, VIM::EsxcliNamespace]
  case o
  when VIM::EsxcliCommand
    cmd = o
    parser = cmd.option_parser
    begin
      opts = parser.parse args
    rescue Trollop::CommandlineError
      err "error: #{$!.message}"
    rescue Trollop::HelpNeeded
      parser.educate
      return
    end
    begin
      pp cmd.call(opts)
    rescue RbVmomi::Fault
      puts "cause: #{$!.faultCause}" if $!.faultCause
      $!.faultMessage.each { |x| puts x }
      $!.errMsg.each { |x| puts "error: #{x}" }
    end
  when VIM::EsxcliNamespace
    ns = o
    unless ns.commands.empty?
      puts "Available commands:"
      ns.commands.each do |k,v|
        puts "#{k}: #{v.help}"
      end
      puts unless ns.namespaces.empty?
    end
    unless ns.namespaces.empty?
      puts "Available namespaces:"
      ns.namespaces.each do |k,v|
        puts "#{k}: #{v.help}"
      end
    end
  end
end

rvc_alias :execute, :esxcli
rvc_alias :execute, :x
