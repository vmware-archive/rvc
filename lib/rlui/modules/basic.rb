include RLUI::Util

def type name
  klass = RbVmomi::VIM.type(name) rescue err("invalid type #{name.inspect}")
  q = lambda { |x| x =~ /^xsd:/ ? $' : x }
  if klass < RbVmomi::VIM::DataObject
    puts "Data Object #{klass}"
    klass.full_props_desc.each do |desc|
      puts " #{desc['name']}: #{q[desc['wsdl_type']]}#{desc['is-array'] ? '[]' : ''}"
    end
  elsif klass < RbVmomi::VIM::ManagedObject
    puts "Managed Object #{klass}"
    puts
    puts "Properties:"
    klass.full_props_desc.each do |desc|
      puts " #{desc['name']}: #{q[desc['wsdl_type']]}#{desc['is-array'] ? '[]' : ''}"
    end
    puts
    puts "Methods:"
    klass.full_methods_desc.sort_by(&:first).each do |name,desc|
      params = desc['params']
      puts " #{name}(#{params.map { |x| "#{x['name']} : #{q[x['wsdl_type'] || 'void']}#{x['is-array'] ? '[]' : ''}" } * ', '}) : #{q[desc['result']['wsdl_type'] || 'void']}"
    end
  else
    err("cannot introspect type #{klass}")
  end
  nil
end

def help
  puts(<<-EOS)
list - List all VMs. <id> is the first column.
on/off/reset/suspend id - VM power operations
register datastore path - Register a VM already in a datastore
unregister id - Unregister a VM from hostd
findvm [datastore] - Display a menu of VMX files to register
destroy id - Unregister VM and delete its files (DESTRUCTIVE)
kill id - Power off and destroy a VM (DESTRUCTIVE)
info id - Information about a VM
view id - Open a VMRC to this VM
ip id - Wait for the VM to get an IP, then display it
ssh id - SSH to this VM
rlui id - Run rlui against this VM
gdb id - Run debug-esx against this VM
ddt id - Run ddt-esx against this VM
ping id - Ping the VM
layout id - VM files information
devices id - List devices
computers - List compute resources in this datacenter
datastores - List datastores in this datacenter
networks - List networks in this datacenter
answer id choice - Answer a VM question
connect id label - Connect a virtual device
disconnect id label - Disconnect a virtual device
extraConfig [regex] - Display extraConfig options
setExtraConfig id key=value - Set extraConfig options
type name - Show the definition of a VMODL type
soap - Toggle display of SOAP messages
rc - Reload ~/.rluirc
  EOS
end

def debug
  $vim.debug = !$vim.debug
end

def quit
  exit
end

def rc
  RLUI.reload_rc
end

def reload
  RLUI.reload_modules
end

def cd path="/"
  $context.cd path
end

LS_SELECT_SET = [
  VIM.TraversalSpec(
    :name => 'tsFolderChildren',
    :type => 'Folder',
    :path => 'childEntity',
    :skip => false
  ),
  VIM.TraversalSpec(
    :name => 'tsComputeResourceHosts',
    :type => 'ComputeResource',
    :path => 'host',
    :skip => false
  ),
  VIM.TraversalSpec(
    :name => 'tsComputeResourceResourcePools',
    :type => 'ComputeResource',
    :path => 'resourcePool',
    :skip => false
  ),
  VIM.TraversalSpec(
    :name => 'tsResourcePoolChildren',
    :type => 'ResourcePool',
    :path => 'resourcePool',
    :skip => false
  ),
  VIM.TraversalSpec(
    :name => 'tsDatacenterVmFolder',
    :type => 'Datacenter',
    :path => 'vmFolder',
    :skip => false
  ),
  VIM.TraversalSpec(
    :name => 'tsDatacenterHostFolder',
    :type => 'Datacenter',
    :path => 'hostFolder',
    :skip => false
  ),
  VIM.TraversalSpec(
    :name => 'tsDatacenterNetworkFolder',
    :type => 'Datacenter',
    :path => 'networkFolder',
    :skip => false
  ),
  VIM.TraversalSpec(
    :name => 'tsDatacenterDatastoreFolder',
    :type => 'Datacenter',
    :path => 'datastoreFolder',
    :skip => false
  ),
]

LS_PROPS = {
  :Folder => %w(name),
  :ComputeResource => %w(name summary.effectiveCpu summary.effectiveMemory),
  :ClusterComputeResource => %w(name summary.effectiveCpu summary.effectiveMemory),
  :HostSystem => %w(name summary.hardware.memorySize summary.hardware.cpuModel
                    summary.hardware.cpuMhz summary.hardware.numCpuPkgs
                    summary.hardware.numCpuCores summary.hardware.numCpuThreads),
  :ResourcePool => %w(name config.cpuAllocation config.memoryAllocation),
  :ManagedEntity => %w(name),
  :Datastore => %w(name summary.capacity summary.freeSpace),
  :VirtualMachine => %w(name runtime.powerState),
  :Network => %w(name),
  :DistributedVirtualPortgroup => %w(name config.distributedVirtualSwitch),
  :DistributedVirtualSwitch => %w(name summary.description),
}

def ls
  cur = $context.cur

  propSet = LS_PROPS.map { |k,v| { :type => k, :pathSet => v } }

  filterSpec = VIM.PropertyFilterSpec(
    :objectSet => [
      {
        :obj => cur,
        :skip => true,
        :selectSet => LS_SELECT_SET,
      }
    ],
    :propSet => propSet
  )

  results = $vim.propertyCollector.RetrieveProperties(:specSet => [filterSpec])

  $context.clear_items
  results.each do |r|
    i = $context.add_item r['name'], r.obj
    case r.obj
    when VIM::Folder
      puts "#{i} #{r['name']}/"
    when VIM::ClusterComputeResource
      puts "#{i} #{r['name']} (cluster): cpu #{r['summary.effectiveCpu']/1000} GHz, memory #{r['summary.effectiveMemory']/1000} GB"
    when VIM::ComputeResource
      puts "#{i} #{r['name']} (standalone): cpu #{r['summary.effectiveCpu']/1000} GHz, memory #{r['summary.effectiveMemory']/1000} GB"
    when VIM::HostSystem
      memorySize, cpuModel, cpuMhz, numCpuPkgs, numCpuCores =
        %w(memorySize cpuModel cpuMhz numCpuPkgs numCpuCores).map { |x| r["summary.hardware.#{x}"] }
      puts "#{i} #{r['name']} (host): cpu #{numCpuPkgs}*#{numCpuCores}*#{"%.2f" % (cpuMhz.to_f/1000)} GHz, memory #{"%.2f" % (memorySize/10**9)} GB"
    when VIM::ResourcePool
      cpuAlloc, memAlloc = r['config.cpuAllocation'], r['config.memoryAllocation']

      cpu_shares_text = cpuAlloc.shares.level == 'custom' ? cpuAlloc.shares.shares.to_s : cpuAlloc.shares.level
      mem_shares_text = memAlloc.shares.level == 'custom' ? memAlloc.shares.shares.to_s : memAlloc.shares.level

      puts "#{i} #{r['name']} (resource pool): cpu %0.2f/%0.2f/%s, mem %0.2f/%0.2f/%s" % [
        cpuAlloc.reservation/1000.0, cpuAlloc.limit/1000.0, cpu_shares_text,
        memAlloc.reservation/1000.0, memAlloc.limit/1000.0, mem_shares_text,
      ]
    when VIM::Datastore
      pct_used = 100*(1-(r['summary.freeSpace'].to_f/r['summary.capacity']))
      pct_used_text = "%0.1f%%" % pct_used
      capacity_text = "%0.2fGB" % (r['summary.capacity'].to_f/10**9)
      puts "#{i} #{r['name']} #{capacity_text} #{pct_used_text}"
    when VIM::VirtualMachine
      puts "#{i} #{r['name']} #{r['runtime.powerState']}"
    when VIM::DistributedVirtualPortgroup
      # XXX optimize
      puts "#{i} #{r['name']} (dvpg) <#{r['config.distributedVirtualSwitch'].name}"
    when VIM::DistributedVirtualSwitch
      puts "#{i} #{r['name']} (dvs)"
    when VIM::Network
      puts "#{i} #{r['name']}"
    else
      puts "#{i} #{r['name']}"
    end
  end
end

def info path
  obj = lookup(path)
  expect obj, VIM::ManagedEntity
  obj.display_info
end
