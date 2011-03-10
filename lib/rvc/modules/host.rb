opts :reboot do
  summary "Reboot a host"
  usage "[opts] path..."
  opt :force, "Reboot even if in maintenance mode", :default => false
end

def reboot args, opts
  progress args, :RebootHost, :force => opts[:force]
end
