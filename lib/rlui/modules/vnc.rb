include RLUI::Util

VNC = ENV['VNC'] || search_path('vinagre') || search_path('tightvnc')

def help
  puts(<<-EOS)
vnc view id - Open a VNC to this VM
vnc off id - Close the VNC port
  EOS
end

def view id
  vm = vm(id)
  ip = reachable_ip vm.runtime.host

  extraConfig = vm.config.extraConfig
  already_enabled = extraConfig.find { |x| x.key == 'RemoteDisplay.vnc.enabled' && x.value.downcase == 'true' }
  if already_enabled
    puts "VNC already enabled"
    port = extraConfig.find { |x| x.key == 'RemoteDisplay.vnc.port' }.value
    password = extraConfig.find { |x| x.key == 'RemoteDisplay.vnc.password' }.value
  else
    port = unused_vnc_port ip
    password = vnc_password
    vm.ReconfigVM_Task(:spec => {
      :extraConfig => [
        { :key => 'RemoteDisplay.vnc.enabled', :value => 'true' },
        { :key => 'RemoteDisplay.vnc.password', :value => password },
        { :key => 'RemoteDisplay.vnc.port', :value => port.to_s }
      ]
    }).wait_for_completion
  end
  vnc_client ip, port, password
end

def off id
  vm(id).ReconfigVM_Task(:spec => {
    :extraConfig => [
      { :key => 'RemoteDisplay.vnc.enabled', :value => 'false' },
      { :key => 'RemoteDisplay.vnc.password', :value => '' },
      { :key => 'RemoteDisplay.vnc.port', :value => '' }
    ]
  }).wait_for_completion
end

private

def reachable_ip host
  ips = host.config.network.vnic.map { |x| x.spec.ip.ipAddress } # TODO optimize
  ips.find do |x|
    begin
      Timeout.timeout(1) { TCPSocket.new(x, 443).close; true }
    rescue
      false
    end
  end or err("could not find IP for server #{host.name}")
end

def unused_vnc_port ip
  10.times do
    port = 5901 + rand(64)
    unused = (TCPSocket.connect(ip, port).close rescue true)
    return port if unused
  end
  err "no unused port found"
end

# Override this if you don't want a random password
def vnc_password
  n = 8
  chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890'
  (0...n).map { chars[rand(chars.length)].chr }.join
end

# Override this to spawn a VNC client differently
def vnc_client ip, port, password
  if VNC
    fork do
      $stderr.reopen("#{ENV['HOME']||'.'}/.rlui-vmrc.log", "w")
      Process.setpgrp
      exec VNC, "#{ip}:#{port}"
    end
    puts "spawning #{VNC}"
    puts "#{ip}:#{port} password: #{password}"
  else
    puts "no VNC client configured"
    puts "#{ip}:#{port} password: #{password}"
  end
end
