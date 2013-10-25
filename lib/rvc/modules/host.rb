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

require 'rvc/vim'
require 'net/ssh'

opts :reboot do
  summary "Reboot hosts"
  arg :host, nil, :lookup => VIM::HostSystem, :multi => true
  opt :force, "Reboot even if not in maintenance mode", :default => false
  opt :wait, "Wait for the host to be connected again", :type => :boolean
end

def reboot hosts, opts
  tasks hosts, :RebootHost, :force => opts[:force]

  if opts[:wait]
    puts "Waiting for hosts to reboot ..."
    # There is no proper way to wait for a host to reboot, so we
    # implement a heuristic that is close enough:
    # First we wait for a moment to give the host time to actually
    # disconnect. Then we just wait for it to be responding again.
    sleep 3 * 60

    hosts.each do |host|
      # We could use the property collector here to wait for an
      # update instead of polling.
      while !(host.runtime.connectionState == "connected" && host.runtime.powerState == "poweredOn")
        sleep 10
      end
      puts "Host #{host.name} is back up"
    end
  end
end

opts :restart_services do
  summary "Restart all services in hosts"
  arg :host, nil, :lookup => VIM::HostSystem, :multi => true
  opt :password, "Host Password", :default => ''
end

def restart_services hosts, opts

  hosts.each do |host|
    Net::SSH.start(host.name, "root", :password => opts[:password], :paranoid => false) do |ssh|
      cmd = "/sbin/chkconfig usbarbitrator off"
      puts "Running #{cmd}"
      out = ssh_exec!(ssh,cmd)
      if out[2] != 0
        puts "Failed to execute #{cmd} on host #{host.name}"
        puts out[1]
      end

      cmd = "/sbin/services.sh restart > /tmp/restart_services.log 2>&1"
      puts "Running #{cmd}"
      out = ssh_exec!(ssh,cmd)
      if out[2] != 0
        puts "Failed to restart all services on host #{host.name}" 
        puts out[1]
      else
        puts "Host #{host.name} restarted all services"
      end 
    end
  end
end


opts :evacuate do
  summary "vMotion all VMs away from this host (experimental)"
  arg :src, nil, :lookup => VIM::HostSystem
  arg :dst, nil, :lookup => VIM::ComputeResource, :multi => true
  opt :num, "Maximum concurrent vMotions", :default => 4
end

def evacuate src, dsts, opts
  vim = src._connection
  vms = src.vm
  dst_hosts = dsts.map(&:host).flatten
  checks = ['cpu', 'software']

  dst_hosts.reject! { |host| host == src ||
                             host.runtime.connectionState != 'connected' ||
                             host.runtime.inMaintenanceMode }

  candidates = {}
  vms.each do |vm|
    required_datastores = vm.datastore
    result = vim.serviceInstance.QueryVMotionCompatibility(:vm => vm,
                                                           :host => dst_hosts,
                                                           :compatibility => checks)
    result.reject! { |x| x.compatibility != checks ||
                         x.host.datastore & required_datastores != required_datastores }
    candidates[vm] = result.map { |x| x.host }
  end

  if candidates.any? { |vm,hosts| hosts.empty? }
    puts "The following VMs have no compatible vMotion destination:"
    candidates.select { |vm,hosts| hosts.empty? }.each { |vm,hosts| puts " #{vm.name}" }
    return
  end

  tasks = candidates.map do |vm,hosts|
    host = hosts[rand(hosts.size)]
    vm.MigrateVM_Task(:host => host, :priority => :defaultPriority)
  end

  progress tasks
end


opts :enter_maintenance_mode do
  summary "Put hosts into maintenance mode"
  arg :host, nil, :lookup => VIM::HostSystem, :multi => true
  opt :timeout, "Timeout", :default => 0
  opt :evacuate_powered_off_vms, "Evacuate powered off vms", :type => :boolean
  opt :no_wait, "Don't wait for Task to complete", :type => :boolean
end

def enter_maintenance_mode hosts, opts
  if opts[:no_wait]
    hosts.each do |host|
      host.EnterMaintenanceMode_Task(:timeout => opts[:timeout], :evacuatePoweredOffVms => opts[:evacuate_powered_off_vms])
    end
  else
    tasks hosts, :EnterMaintenanceMode, :timeout => opts[:timeout], :evacuatePoweredOffVms => opts[:evacuate_powered_off_vms]
  end
end


opts :exit_maintenance_mode do
  summary "Take hosts out of maintenance mode"
  arg :host, nil, :lookup => VIM::HostSystem, :multi => true
  opt :timeout, "Timeout", :default => 0
end

def exit_maintenance_mode hosts, opts
  tasks hosts, :ExitMaintenanceMode, :timeout => opts[:timeout]
end


opts :disconnect do
  summary "Disconnect a host"
  arg :host, nil, :lookup => VIM::HostSystem, :multi => true
end

def disconnect hosts
  tasks hosts, :DisconnectHost
end


opts :reconnect do
  summary "Reconnect a host"
  arg :host, nil, :lookup => VIM::HostSystem, :multi => true
  opt :username, "Username", :short => 'u', :default => 'root'
  opt :password, "Password", :short => 'p', :default => ''
end

def reconnect hosts, opts
  spec = {
    :force => false,
    :userName => opts[:username],
    :password => opts[:password],
  }
  tasks hosts, :ReconnectHost
end


opts :add_iscsi_target do
  arg :host, nil, :lookup => VIM::HostSystem, :multi => true
  opt :address, "Address of iSCSI server", :short => 'a', :type => :string, :required => true
  opt :iqn, "IQN of iSCSI target", :short => 'i', :type => :string, :required => true
  opt :dynamic_target, "Use Dynamic target Discovery", :short => 'd', :type => :boolean
end

def add_iscsi_target hosts, opts
  hosts.each do |host|
    puts "configuring host #{host.name}"
    storage = host.configManager.storageSystem
    storage.UpdateSoftwareInternetScsiEnabled(:enabled => true)
    adapter = storage.storageDeviceInfo.hostBusAdapter.grep(VIM::HostInternetScsiHba)[0]
    if opts[:dynamic_target]
      storage.UpdateInternetScsiName(
        :iScsiHbaDevice => adapter.device,
        :iScsiName => opts[:iqn]
      )
      storage.AddInternetScsiSendTargets(
        :iScsiHbaDevice => adapter.device,
        :targets => [
          VIM::HostInternetScsiHbaSendTarget(:address => opts[:address])
        ]
      )
    else
      storage.AddInternetScsiStaticTargets(
        :iScsiHbaDevice => adapter.device,
        :targets => [
          VIM::HostInternetScsiHbaStaticTarget(
            :address => opts[:address],
            :iScsiName => opts[:iqn])
        ]
      )
    end
    storage.RescanAllHba
  end
end

opts :add_nfs_datastore do
  arg :host, nil, :lookup => VIM::HostSystem, :multi => true
  opt :name, "Datastore name", :short => 'n', :type => :string, :required => true
  opt :address, "Address of NFS server", :short => 'a', :type => :string, :required => true
  opt :path, "Path on NFS server", :short => 'p', :type => :string, :required => true
end

def add_nfs_datastore hosts, opts
  hosts.each do |host|
    datastoreSystem, = host.collect 'configManager.datastoreSystem'
    spec = {
      :accessMode => 'readWrite',
      :localPath => opts[:name],
      :remoteHost => opts[:address],
      :remotePath => opts[:path]
    }
    datastoreSystem.CreateNasDatastore :spec => spec
  end
end


opts :rescan_storage do
  summary "Rescan HBAs and VMFS"
  arg :host, nil, :lookup => VIM::HostSystem, :multi => true
end

def rescan_storage hosts
  hosts.each do |host|
    storageSystem = host.configManager.storageSystem
    storageSystem.RescanAllHba
    storageSystem.RescanVmfs
  end
end


opts :select_vmknic_for_service do
  summary "Selects a vmknic for a particular service"
  arg :vmknic, "Name of vmknic", :type => :string
  arg :service, "e.g.: vmotion", :type => :string
  arg :host, nil, :lookup => VIM::HostSystem, :multi => true
end

def select_vmknic_for_service vmknic, service, hosts
  hosts.each do |host|
    vnicSys = host.configManager.virtualNicManager
    vnicSys.SelectVnicForNicType(:nicType => service, :device => vmknic)
  end
end


opts :deselect_vmknic_for_service do
  summary "Selects a vmknic for a particular service"
  arg :vmknic, "Name of vmknic", :type => :string
  arg :service, "e.g.: vmotion", :type => :string
  arg :host, nil, :lookup => VIM::HostSystem, :multi => true
end

def deselect_vmknic_for_service vmknic, service, hosts
  hosts.each do |host|
    vnicSys = host.configManager.virtualNicManager
    vnicSys.DeselectVnicForNicType(:nicType => service, :device => vmknic)
  end
end

# http://stackoverflow.com/questions/3386233/how-to-get-exit-status-with-rubys-netssh-library
def ssh_exec!(ssh, command)
  stdout_data = ""
  stderr_data = ""
  exit_code = nil
  exit_signal = nil
  ssh.open_channel do |channel|
    channel.exec(command) do |ch, success|
      unless success
        abort "FAILED: couldn't execute command (ssh.channel.exec)"
      end
      channel.on_data do |ch,data|
        stdout_data+=data
      end

      channel.on_extended_data do |ch,type,data|
        stderr_data+=data
      end

      channel.on_request("exit-status") do |ch,data|
        exit_code = data.read_long
      end

    end
  end
  ssh.loop
  [stdout_data, stderr_data, exit_code]
end
