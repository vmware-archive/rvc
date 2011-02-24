include RLUI::Util

def list
  tree = $dc.networkFolder.inventory(:Network => %w(name host vm))
  display_inventory tree, $dc.networkFolder do |obj,props,indent|
    num_hosts = props['host'].size
    num_vms = props['vm'].size
    puts "#{"  "*indent}#{props['name']}: #{num_hosts} hosts, #{num_vms} vms"
  end
end

def info id
  net = item(id)
  case net
  when VIM::DistributedVirtualPortgroup
    config, = net.collect(:config)
    puts "name: #{config.name}"
    puts "ports: #{config.numPorts}"
    puts "description: #{config.description}"
    puts "switch: #{config.distributedVirtualSwitch.name}"
  when VIM::DistributedVirtualSwitch
    config, = net.collect(:config)
    puts "name: #{config.name}"
    puts "description: #{config.description}"
    puts "product: #{config.productInfo.vendor} #{config.productInfo.name} #{config.productInfo.version}"
    puts "ports: #{config.numPorts}"
    puts "standalone ports: #{config.numStandalonePorts}"
    puts "maximum ports: #{config.maxPorts}"
    puts "netIORM: #{config.networkResourceManagementEnabled}"
  when VIM::Network
    summary, = net.collect(:summary)
    puts "name: #{summary.name}"
    puts "accessible: #{summary.accessible}"
    puts "IP pool name: #{summary.ipPoolName}" unless summary.ipPoolName.empty?
  else
    err "unexpected type"
  end
end
