class RbVmomi::VIM::DistributedVirtualPortgroup
  def display_info
    config, = collect(:config)
    puts "name: #{config.name}"
    puts "ports: #{config.numPorts}"
    puts "description: #{config.description}"
    puts "switch: #{config.distributedVirtualSwitch.name}"
  end

  def self.ls_properties
    %w(name config.distributedVirtualSwitch)
  end

  def self.ls_text r
    # XXX optimize
    " (dvpg): <#{r['config.distributedVirtualSwitch'].name}"
  end
end
