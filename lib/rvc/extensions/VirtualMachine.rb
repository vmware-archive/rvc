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
    RVC::Util.err "Information currently unavailable" unless config and runtime and guest

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
      'datastores' => RVC::FakeFolder.new(self, :rvc_children_datastores),
      'networks' => RVC::FakeFolder.new(self, :rvc_children_networks),
      'files' => RVC::FakeFolder.new(self, :rvc_children_files),
      'snapshots' => RVC::RootSnapshotFolder.new(self),
    }
  end

  def rvc_children_datastores
    RVC::Util.collect_children self, :datastore
  end

  def rvc_children_networks
    RVC::Util.collect_children self, :network
  end

  def rvc_children_files
    files = layoutEx.file
    datastore_map = RVC::Util.collect_children self, :datastore
    Hash[files.map do |file|
      file.name =~ /^\[(.+)\] (.+)$/ or fail "invalid datastore path"
      ds = datastore_map[$1] or fail "datastore #{$1.inspect} not found"
      arcs, = RVC::Path.parse $2
      arcs.unshift 'files'
      objs = $shell.fs.traverse ds, arcs
      fail unless objs.size == 1
      [File.basename(file.name), objs.first]
    end]
  end
end

class RVC::RootSnapshotFolder
  include RVC::InventoryObject

  def initialize vm
    @vm = vm
  end

  def children
    info = @vm.snapshot
    return {} unless info
    Hash[info.rootSnapshotList.map { |x| [x.name, RVC::SnapshotFolder.new(@vm, [x.id])] }]
  end

  def display_info
    puts "Root of a VM's snapshot tree"
  end
end

class RVC::SnapshotFolder
  include RVC::InventoryObject

  def initialize vm, ids
    @vm = vm
    @ids = ids
  end

  def self.to_s
    'Snapshot'
  end

  def find_tree
    cur = nil
    info = @vm.snapshot
    fail "snapshot not found" unless info
    children = info.rootSnapshotList
    @ids.each do |id|
      cur = children.find { |x| x.id == id }
      fail "snapshot not found" unless cur
      children = cur.childSnapshotList
    end
    cur
  end

  def children
    tree = find_tree
    {}.tap do |h|
      tree.childSnapshotList.each do |x|
        name = x.name
        name = x.name + '.1' if h.member? x.name
        while h.member? name
          name = name.succ
        end
        h[name] = RVC::SnapshotFolder.new(@vm, @ids+[x.id])
      end
    end
  end

  def display_info
    tree = find_tree
    puts "id: #{tree.id}"
    puts "name: #{tree.name}"
    puts "description: #{tree.description}"
    puts "state: #{tree.state}"
    puts "creation time: #{tree.createTime}"
  end
end
