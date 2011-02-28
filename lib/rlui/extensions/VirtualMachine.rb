class RbVmomi::VIM::VirtualMachine
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
    config.hardware.device.grep RbVmomi::VIM::VirtualEthernetCard do |dev|
      backing_info = case dev.backing
      when RbVmomi::VIM::VirtualEthernetCardNetworkBackingInfo
        dev.backing.deviceName.inspect
      when RbVmomi::VIM::VirtualEthernetCardDistributedVirtualPortBackingInfo
        dev.backing.port.portgroupKey.inspect
      else
        dev.backing.class.name
      end
      guest_net = guest.net.find { |x| x.macAddress == dev.macAddress }
      puts " #{dev.deviceInfo.label}: #{backing_info} #{dev.connectable.connected ? :connected : :disconnected} #{dev.macAddress} #{guest_net ? (guest_net.ipAddress * ' ') : ''}"
    end
  end
end
