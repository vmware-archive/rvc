def reboot *paths
  progress paths, :RebootHost, :force => false
end

def reboot! *paths
  progress paths, :RebootHost, :force => true
end
