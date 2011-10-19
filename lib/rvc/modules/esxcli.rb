raw_opts :execute, "Execute an esxcli command"

def execute *args
  path = args.shift or err "esxcli path argument required"
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
      puts "#{$!.message}"
      puts "cause: #{$!.faultCause}" if $!.respond_to? :faultCause and $!.faultCause
      $!.faultMessage.each { |x| puts x } if $!.respond_to? :faultMessage
      $!.errMsg.each { |x| puts "error: #{x}" } if $!.respond_to? :errMsg
    end
  when VIM::EsxcliNamespace
    ns = o
    unless ns.commands.empty?
      puts "Available commands:"
      ns.commands.each do |k,v|
        puts "#{k}: #{v.cli_info.help}"
      end
      puts unless ns.namespaces.empty?
    end
    unless ns.namespaces.empty?
      puts "Available namespaces:"
      ns.namespaces.each do |k,v|
        puts "#{k}: #{v.cli_info.help}"
      end
    end
  end
end

rvc_alias :execute, :esxcli
rvc_alias :execute, :x
