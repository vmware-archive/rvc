# Copyright (c) 2011 VMware, Inc.  All Rights Reserved.
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

VNC = ENV['VNC'] || search_path('vinagre') || search_path('tightvnc') || search_path('vncviewer')

opts :view do
  summary "Spawn a VNC client"
  arg :vm, nil, :lookup => VIM::VirtualMachine
end

rvc_alias :view, :vnc
rvc_alias :view, :V

def view vm
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


opts :off do
  summary "Close a VM's VNC port"
  arg :vm, nil, :lookup => VIM::VirtualMachine
end

def off vm
  vm.ReconfigVM_Task(:spec => {
    :extraConfig => [
      { :key => 'RemoteDisplay.vnc.enabled', :value => 'false' },
      { :key => 'RemoteDisplay.vnc.password', :value => '' },
      { :key => 'RemoteDisplay.vnc.port', :value => '' }
    ]
  }).wait_for_completion
end


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
# 
# We can save the vnc pasword out to a file, then call vncviewer with it
# directly so we don't need to "password" auth.
def vnc_client ip, port, password

  unless VNC
    puts "no VNC client configured"
    return false
  end

  unless VNC =~ /\/vncviewer/ # or other vnc clients that support the same -passwd
    vnc_client_connect ip, port, password
  else

    file = Tempfile.new( 'rvcvncpass' )
    filename = file.path
    begin

      IO.popen( "vncpasswd #{filename}" , 'w+' ) do |vncpass| 
        vncpass.puts password
        vncpass.puts password
      end

      vnc_client_connect ip, port, password, "-passwd #{filename} "
    ensure
      sleep 3 # we have to do this, as the vncviewer forks, and we've no simple way of working out if that thread has read the file yet.
      file.close
      file.unlink
    end
  end

end

def vnc_client_connect ip, port, password, vnc_opts=nil
  fork do
    $stderr.reopen("#{ENV['HOME']||'.'}/.rvc-vmrc.log", "w")
    Process.setpgrp
    exec VNC, "#{vnc_opts} #{ip}:#{port}"
  end
  puts "spawning #{VNC}"
  print "#{ip}:#{port} password: #{password}"
  print " options: #{vnc_opts}" unless vnc_opts.nil?
  puts
end

