opts :reboot do
  summary "Reboot a host"
  arg :path, 'HostSystem', :multi => true
  opt :force, "Reboot even if in maintenance mode", :default => false
end

def reboot paths, opts
  progress paths, :RebootHost, :force => opts[:force]
end
