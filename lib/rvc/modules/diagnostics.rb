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


opts :vm_create do
  summary "Check that VMs can be created on all hosts in a cluster"
  arg :cluster, nil, :lookup => VIM::ComputeResource, :multi => true
  opt :datastore, "Datastore to put (temporary) VMs on", :lookup => VIM::Datastore
  opt :vm_folder, "VM Folder to place (temporary) VMs in", :lookup => VIM::Folder
  opt :timeout, "Time to wait for VM creation to finish", :type => :int, :default => 3 * 60
end

def vm_create clusters, opts
  datastore = opts[:datastore]
  vm_folder = opts[:vm_folder]
  err "datastore is a required parameter" unless datastore
  err "vm_folder is a required parameter" unless vm_folder

  puts "Creating one VM per host ... (timeout = #{opts[:timeout]} sec)"
  result = _vm_create clusters, datastore, vm_folder, opts

  errors = result.select{|h, x| x['status'] != 'green'}
  errors.each do |host, info|
    puts "Failed to create VM on host #{host} (in cluster #{info['cluster']}): #{info['error']}"
  end
  if errors.length == 0
    puts "Success"
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
      task = vm_folder.CreateVM_Task(:config => config,
                                     :pool => rp,
                                     :host => host)
      tasks_map[task] = host
      hosts_infos[host][:create_task] = task
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
    if result == nil
      error_str = nil
      status = 'green'
    elsif result.is_a?(String)
      error_str = result
      status = 'red'
    else
      error_str = "#{result.fault.class.wsdl_name}: #{result.localizedMessage}"
      status = 'red'
    end

    out[host_props['name']] = {
      'cluster' => cluster_props['name'],
      'status' => status,
      'error' => error_str
    }    
  end
  out
end
