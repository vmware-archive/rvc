class RbVmomi::VIM::DistributedVirtualPortgroup
  def display_info
    config, = collect(:config)
    puts "name: #{config.name}"
    puts "ports: #{config.numPorts}"
    puts "description: #{config.description}"
    puts "switch: #{config.distributedVirtualSwitch.name}"
  end
end
