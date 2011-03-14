opts :reboot do
  summary "Reboot a host"
  arg :host, nil, :lookup => VIM::HostSystem, :multi => true
  opt :force, "Reboot even if in maintenance mode", :default => false
end

def reboot hosts, opts
  progress hosts, :RebootHost, :force => opts[:force]
end
