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

class RbVmomi::VIM::VirtualMachine
  def display_info
    config, runtime, guest = collect :config, :runtime, :guest
    err "Information currently unavailable" unless config and runtime and guest

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

  def self.ls_properties
    %w(name runtime.powerState)
  end
  
  def ls_text r
    ": #{r['runtime.powerState']}"
  end

  def children
    host, resourcePool = collect *%w(runtime.host resourcePool)
    {
      'host' => host,
      'resourcePool' => resourcePool,
    }
  end
end
