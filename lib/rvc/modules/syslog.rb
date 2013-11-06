# Copyright (c) 2013 VMware, Inc.  All Rights Reserved.
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

begin
  require 'net/ssh'
rescue LoadError
end

opts :config_syslog do
  summary "Configure Syslog"
  arg :entity, nil, :lookup => [VIM, VIM::HostSystem, VIM::ComputeResource, VIM::ClusterComputeResource]
  arg :ip, nil, :type => :string
  opt :vc_root_pwd, "VC root password for SSH access", :default => "vmware"
end

def config_syslog entity, ip, opts
  if entity.is_a?(VIM)
    puts "#{Time.now}: Finding all Hosts inside VC"
    $shell.fs.marks['vcrvc'] = entity
    hosts = []
    hosts += $shell.fs.lookup("~vcrvc/*/computers/*/host")
    hosts += $shell.fs.lookup("~vcrvc/*/computers/*/hosts/*")
  elsif entity.is_a?(VIM::ComputeResource)
    hosts = entity.host
  else
    hosts = [entity]
  end
  if hosts.length == 0
    err "No hosts found"
  end
  conn = hosts.first._connection
  pc = conn.propertyCollector
  
  lock = Mutex.new
  hosts_props = pc.collectMultiple(hosts,
    'name', 
    'runtime.connectionState',
  )
  connected_hosts = hosts_props.select do |k,v| 
    v['runtime.connectionState'] == 'connected'
  end.keys
  host = connected_hosts.first
  if !connected_hosts.first
    err "Couldn't find any connected hosts"
  end

  puts "#{Time.now}: Configuring all ESX hosts ..."
  loghost = "udp://#{ip}:514"
  hosts.map do |host|
    Thread.new do
      begin 
        c1 = conn.spawn_additional_connection
        host  = host.dup_on_conn(c1)
        hostName = host.name
        lock.synchronize do 
          puts "#{Time.now}: Configuring syslog on #{hostName}"
        end
        syslog = host.esxcli.system.syslog
        syslog.config.set(:loghost => loghost)
        syslog.reload
      rescue Exception => ex
        puts "#{Time.now}: #{host.name}: Got exception: #{ex.class}: #{ex.message}"
      end
    end
  end.each{|t| t.join}
  puts "#{Time.now}: Done configuring syslog on all hosts"
  
  local = "#{File.dirname(__FILE__)}/configurevCloudSuiteSyslog.sh"
  osType = conn.serviceContent.about.osType
  if File.exists?(local) && osType == "linux-x64"
    puts "#{Time.now}: Configuring VCVA ..."
    Net::SSH.start(conn.host, "root", :password => opts[:vc_root_pwd], 
                   :paranoid => false) do |ssh|
      ssh.scp.upload!(local, "/tmp/configurevCloudSuiteSyslog.sh")
      cmd = "sh /tmp/configurevCloudSuiteSyslog.sh vcsa #{ip}"
      puts "#{Time.now}: Running '#{cmd}' on VCVA"
      puts ssh.exec!(cmd)
    end
    puts "#{Time.now}: Done with VC"
  else
    puts "#{Time.now}: VC isn't Linux, skipping ..."
  end
  puts "#{Time.now}: Done"
end
