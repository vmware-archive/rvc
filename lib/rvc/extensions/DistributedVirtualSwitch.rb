class RbVmomi::VIM::DistributedVirtualSwitch
  def display_info
    config, = collect(:config)
    puts "name: #{config.name}"
    puts "description: #{config.description}"
    puts "product: #{config.productInfo.vendor} #{config.productInfo.name} #{config.productInfo.version}"
    puts "ports: #{config.numPorts}"
    puts "standalone ports: #{config.numStandalonePorts}"
    puts "maximum ports: #{config.maxPorts}"
    puts "netIORM: #{config.networkResourceManagementEnabled}"
  end

  def self.ls_properties
    %w(name summary.description)
  end

  def ls_text r
    " (dvs)"
  end
end
