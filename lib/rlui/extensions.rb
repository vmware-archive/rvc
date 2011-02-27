class RbVmomi::VIM

ManagedEntity
class ManagedEntity
  def display_info
    puts "name: #{name}"
    puts "type: #{self.class.wsdl_name}"
  end

  def child_map
    {}
  end

  def traverse_one arc
    nil
  end
end

ComputeResource
class ComputeResource
  # TODO expand, optimize
  def display_info
    puts "name: #{name}"
    puts "hosts:"
    host.each do |h|
      puts " #{h.name}"
    end
  end
end

Datastore
class Datastore
  def display_info
    s, info, = collect :summary, :info
    puts "type: #{s.type}"
    puts "url: #{s.accessible ? s.url : '<inaccessible>'}"
    puts "uuid: #{info.vmfs.uuid}"
    puts "multipleHostAccess: #{s.multipleHostAccess}"
    puts "capacity: %0.2fGB" % (s.capacity.to_f/10**9)
    puts "free space: %0.2fGB" % (s.freeSpace.to_f/10**9)
  end
end

DistributedVirtualPortgroup
class DistributedVirtualPortgroup
  def display_info
    config, = collect(:config)
    puts "name: #{config.name}"
    puts "ports: #{config.numPorts}"
    puts "description: #{config.description}"
    puts "switch: #{config.distributedVirtualSwitch.name}"
  end
end

DistributedVirtualSwitch
class DistributedVirtualSwitch
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
end

Network
class Network
  def display_info
    summary, = collect(:summary)
    puts "name: #{summary.name}"
    puts "accessible: #{summary.accessible}"
    puts "IP pool name: #{summary.ipPoolName}" unless summary.ipPoolName.empty?
  end
end

VirtualMachine
class VirtualMachine
  def display_info
    config, runtime, guest = collect :config, :runtime, :guest

    puts "name: #{config.name}"
    puts "note: #{config.annotation}" if config.annotation and !config.annotation.empty?
    puts "host: #{runtime.host.path[1..-1].map { |x| x[1] } * '/'}" if runtime.host
    puts "tools: #{guest.toolsRunningStatus}"
    puts "hostname: #{guest.hostName} (#{guest.ipAddress})" if guest.hostName and guest.ipAddress
    puts "VC UUID: #{config.instanceUuid}" if config.instanceUuid and !config.instanceUuid.empty?
    puts "power: #{runtime.powerState}"
    if runtime.question
      puts "question: #{runtime.question.text.lines.to_a.join("> ")}"
      puts "choices: #{runtime.question.choice.choiceInfo.map(&:label) * ', '}"
      if i = runtime.question.choice.defaultIndex
        puts "default: #{runtime.question.choice.choiceInfo[i].label}"
      end
    end
    puts "cpus: #{config.hardware.numCPU}"
    puts "memory: #{config.hardware.memoryMB} MB"

    puts "nics:"
    config.hardware.device.grep VirtualEthernetCard do |dev|
      backing_info = case dev.backing
      when VirtualEthernetCardNetworkBackingInfo
        dev.backing.deviceName.inspect
      when VirtualEthernetCardDistributedVirtualPortBackingInfo
        dev.backing.port.portgroupKey.inspect
      else
        dev.backing.class.name
      end
      guest_net = guest.net.find { |x| x.macAddress == dev.macAddress }
      puts " #{dev.deviceInfo.label}: #{backing_info} #{dev.connectable.connected ? :connected : :disconnected} #{dev.macAddress} #{guest_net ? (guest_net.ipAddress * ' ') : ''}"
    end
  end
end

Folder
class Folder
  def child_map
    Hash[children.map { |x| [x.name, x] }]
  end

  def traverse_one arc
    $vim.searchIndex.find :entity => self, :name => arc
  end
end

Datacenter
class Datacenter
  def child_map
    vmFolder, datastoreFolder, networkFolder, hostFolder =
      collect :vmFolder, :datastoreFolder, :networkFolder, :hostFolder
    {
      'vm' => vmFolder,
      'datastore' => datastoreFolder,
      'network' => networkFolder,
      'host' => hostFolder
    }
  end

  def traverse_one arc
    case arc
    when 'vm' then vmFolder
    when 'datastore' then datastoreFolder
    when 'network' then networkFolder
    when 'host' then hostFolder
    end
  end
end

end
