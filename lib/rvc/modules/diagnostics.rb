# Copyright (c) 2012 VMware, Inc.  All Rights Reserved.
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

DEFAULT_SERVER_PLACEHOLDER = '0.0.0.0'

def wait_for_multiple_tasks tasks, timeout
  if tasks == []
    return []
  end
  pc = tasks.first._connection.serviceContent.propertyCollector
  done = false
  t1 = Time.now
  while !done && (Time.now - t1) < timeout
    tasks_props = pc.collectMultiple(tasks, 'info.state')
    if tasks_props.reject{|t,f| ['success', 'error'].member?(f['info.state'])}.empty?
      done = true
    end
    sleep 2
  end
  tasks_props = pc.collectMultiple(tasks, 'info.state', 'info.error')
  results = Hash[tasks_props.map do |task, props|
    result = if props['info.state'] == 'success'
      task.info.result
    elsif props['info.state'] == 'error'
      props['info.error']
    else
      "Timed out"
    end
    [task, result]
  end]
  results
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

opts :restart_services do
  summary "Restart all services in hosts"
  arg :cluster, nil, :lookup => VIM::ComputeResource, :multi => true
  opt :host, "Host name (multi ok)", type: :string, short: 'n', :multi => true
  opt :password, "Host password (multi ok)", type: :string, short: 'p', :multi => true
end

def restart_services clusters, opts
  hosts = opts[:host]
  pwds = opts[:password]
  puts "Need to specify password(s) for fixing" if pwds == []

  hosts.each do |host|
    finished = false
    pwds.each do |pwd|
      break if finished
      puts "\nTrying restart #{host} with pwd #{pwd}"
      begin
        Net::SSH.start(host, "root", :password => pwd, :paranoid => false) do |ssh|
          # HZ 1258412 discusses the commands to fix a node with hostd problems
          cmd = "/sbin/chkconfig usbarbitrator off"
          puts "Running #{cmd}"
          out = ssh_exec!(ssh,cmd)
          if out[2] != 0
            puts "Failed to execute #{cmd} on host #{host}"
            puts out[1]
          end

          cmd = "/sbin/services.sh restart > /tmp/restart_services.log 2>&1"
          puts "Running #{cmd}"
          out = ssh_exec!(ssh,cmd)
          if out[2] != 0
            puts "Failed to restart all services on host #{host}"
            puts out[1]
          else
            puts "Host #{host} restarted all services"
            finished = true
          end
        end
      rescue Net::SSH::AuthenticationFailed
        puts "Failed to authenticate on host #{host}"
      end
    end
  end
end

opts :vm_create do
  summary "Check that VMs can be created on all hosts in a cluster"
  arg :cluster, nil, :lookup => VIM::ComputeResource, :multi => true
  opt :datastore, "Datastore to put (temporary) VMs on", :lookup => VIM::Datastore
  opt :vm_folder, "VM Folder to place (temporary) VMs in", :lookup => VIM::Folder
  opt :timeout, "Time to wait for VM creation to finish", :type => :int, :default => 3 * 60
  opt :fix, "Fix the failing ESX hosts", :type => :boolean , :default => false
  opt :password, "Passwords for fixing hosts", :type => :string, short: 'p', :multi => true
end

def vm_create clusters, opts
  datastore = opts[:datastore]
  vm_folder = opts[:vm_folder]
  err "datastore is a required parameter" unless datastore
  err "vm_folder is a required parameter" unless vm_folder

  puts "Creating one VM per host ... (timeout = #{opts[:timeout]} sec)"
  errors = []
  failed_hosts = []
  begin
    result = _vm_create clusters, datastore, vm_folder, opts
    errors = result.select{|h, x| x['status'] != 'green'}
    errors.each do |host, info|
      puts "Failed to create VM on host #{host} (in cluster #{info['cluster']}): #{info['error']}"
      err_msgs = ["Timed out", "InvalidState", "InvalidHostState", "InvalidHostConnectionState", "HostCommunication"]
      err_msgs.each do |msg|
        if info['error'].include? msg
          failed_hosts << host
          break
        end
      end
    end
  rescue Exception => e
    puts "An error occurred:\n"
    puts "e.message:", e.message
    puts "e.backtrace:", e.backtrace.join("\n")
    errors = [e]
  end
  if errors.length == 0
    puts "Success"
  end
  if opts[:fix] && failed_hosts != []
    opts[:host] = failed_hosts
    restart_services(clusters, opts)
  end
end

def _vm_create clusters, datastore, vm_folder, opts = {}
  pc = datastore._connection.serviceContent.propertyCollector
  datastore_path = "[#{datastore.name}]"
  run = Time.now.to_i % 1000
  tasks_map = {}
  cluster_host_map = {}
  clusters_props = pc.collectMultiple(clusters, 'name', 'resourcePool', 'host')
  all_hosts = clusters_props.map{|c, p| p['host']}.flatten
  hosts_props = pc.collectMultiple(all_hosts, 'name')

  hosts_infos = Hash[all_hosts.map{|host| [host, {}]}]
  
  clusters.each do |cluster|
    cluster_props = clusters_props[cluster]
    rp = cluster_props['resourcePool']
    hosts = cluster_props['host']
    hosts.map do |host|
      cluster_host_map[host] = cluster
      config = {
        :name => "VM-on-#{hosts_props[host]['name']}-#{run}",
        :guestId => 'otherGuest',
        :files => { :vmPathName => datastore_path },
        :numCPUs => 1,
        :memoryMB => 16,
        :annotation => YAML.dump({'lease' => Time.now + 2 * opts[:timeout] + 60}),
        :deviceChange => [
          {
            :operation => :add,
            :device => VIM.VirtualCdrom(
              :key => -2,
              :connectable => {
                :allowGuestControl => true,
                :connected => true,
                :startConnected => true,
              },
              :backing => VIM.VirtualCdromIsoBackingInfo(
                :fileName => datastore_path
              ),
              :controllerKey => 200,
              :unitNumber => 0
            )
          }
        ],
      }
      begin
        task = vm_folder.CreateVM_Task(:config => config,
                                       :pool => rp,
                                       :host => host)
        tasks_map[task] = host
        hosts_infos[host][:create_task] = task
      rescue
        puts "Failed to create task for host #{host.name}"
      end
    end
  end
  
  create_tasks = tasks_map.keys
  create_results = wait_for_multiple_tasks create_tasks, opts[:timeout]
  create_results.each { |t, r| hosts_infos[tasks_map[t]][:create_result] = r }

  vms = create_results.select{|t, x| x.is_a? VIM::VirtualMachine}
  destroy_tasks = Hash[vms.map{|t, x| [x.Destroy_Task, t]}]

  destroy_results = wait_for_multiple_tasks destroy_tasks.keys, opts[:timeout]
  destroy_results.each do |t, r|
    create_task = destroy_tasks[t]
    hosts_infos[tasks_map[create_task]][:destroy_result] = r 
  end

  out = {}
  all_hosts.each do |host|
    host_info = hosts_infos[host]
    host_props = hosts_props[host]
    cluster = cluster_host_map[host]
    cluster_props = clusters_props[cluster]

    result = host_info[:create_result]
    result = host_info[:destroy_result] if result.is_a?(VIM::VirtualMachine)
    error_detail = nil
    if result == nil
      error_str = nil
      status = 'green'
    elsif result.is_a?(String)
      error_str = result
      status = 'red'
    else
      error_str = "#{result.fault.class.wsdl_name}: #{result.localizedMessage}"
      status = 'red'
      begin
        error_detail = result.fault.faultMessage
      rescue
      end
    end

    out[host_props['name']] = {
      'cluster' => cluster_props['name'],
      'status' => status,
      'error' => error_str,
      'error_detail' => error_detail,
    }    
  end
  out
end
