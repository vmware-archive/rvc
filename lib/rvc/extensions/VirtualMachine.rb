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
  field 'on' do
    summary "Is the VM powered on?"
    properties %w(runtime.powerState)
    block { |powerState| powerState == 'poweredOn' }
    default
  end
  
  field 'storagebw' do
    summary "Storage Bandwidth"
    perfmetrics %w(virtualDisk.read virtualDisk.write)
    block do |read, write| 
      if read && write
        read = read.select{|x| x != -1}
        write = write.select{|x| x != -1}
        if read.length > 0 && write.length > 0
          io = (read.sum.to_f / read.length) + (write.sum.to_f / write.length)
          MetricNumber.new(io * 1024, 'B/s')
        end
      else
        nil
      end
    end
  end
  
  [['', 5], ['.realtime', 3], ['.5min', 5 * 3], ['.10min', 10 * 3]].each do |label, max_samples|
    field "storageiops#{label}" do
      summary "Storage IOPS"
      perfmetrics %w(virtualDisk.numberReadAveraged virtualDisk.numberWriteAveraged)
      perfmetric_settings :max_samples => max_samples
      block do |read, write|
        if read && write
          read = read.select{|x| x != -1}
          write = write.select{|x| x != -1}
          if read.length > 0 && write.length > 0
            io = (read.sum.to_f / read.length) + (write.sum.to_f / write.length)
            MetricNumber.new(io, 'IOPS')
          end
        else
          nil
        end
      end
    end
  end

  ['Read', 'Write'].each do |type|
  [['', 5], ['.realtime', 1], ['.5min', 5 * 3], ['.10min', 10 * 3]].each do |label, max_samples|
    field "storagelatency.#{type.downcase}#{label}" do
      summary "Storage Latency #{type}"
      perfmetrics ["virtualDisk.total#{type}Latency"]
      perfmetric_settings :max_samples => max_samples
      block do |latency|
        if latency
          io = (latency.sum.to_f / latency.length)
          MetricNumber.new(io, 'ms')
        else
          nil
        end
      end
    end
  end
  end

  field 'ip' do
    summary "The guest tools reported IP address."
    property 'guest.ipAddress'
  end

  field 'template' do
    summary "Is this VM a template?"
    property 'config.template'
  end

  field 'uptime' do
    summary "VM's uptime in seconds"
    properties %w(runtime.bootTime)
    block { |t| t ? TimeDiff.new(Time.now-t) : nil }
  end

  field 'storage.used' do
    summary "Total storage used"
    properties %w(storage)
    block do |storage|
      MetricNumber.new(storage.perDatastoreUsage.map(&:committed).sum, 'B')
    end
  end

  field 'storage.unshared' do
    summary "Total storage unshared"
    properties %w(storage)
    block do |storage|
      MetricNumber.new(storage.perDatastoreUsage.map(&:unshared).sum, 'B')
    end
  end

  field 'storage.provisioned' do
    summary "Total storage provisioned"
    properties %w(storage)
    block do |storage|
      MetricNumber.new(storage.perDatastoreUsage.map { |x| x.uncommitted + x.committed }.sum, 'B')
    end
  end

  field 'guest.id' do
    summary 'Guest OS identifier'
    property 'summary.config.guestId'
  end

  field 'tools.running' do
    summary 'Are guest tools running?'
    properties %w(guest.toolsRunningStatus)
    block { |status| status == 'guestToolsRunning' }
  end

  field 'tools.uptodate' do
    summary "Are guest tools up to date?"
    properties %w(guest.toolsVersionStatus)
    block { |status| status == 'guestToolsCurrent' }
  end

  field 'mac' do
    summary "Mac address"
    properties %w(config.hardware)
    block { |hw| hw.device.grep(VIM::VirtualEthernetCard).map(&:macAddress) }
  end

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
    puts "connectionState: #{runtime.connectionState}"
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
      puts " #{dev.name}: #{backing_info} #{dev.connectable.connected ? :connected : :disconnected} #{dev.macAddress} #{guest_net ? (guest_net.ipAddress * ' ') : ''}"
    end

    puts "storage:"
    storage.perDatastoreUsage.map do |usage|
      puts " #{usage.datastore.name}: committed=#{usage.committed.metric}B uncommitted=#{usage.uncommitted.metric}B unshared=#{usage.unshared.metric}B"
    end
    
    if runtime.dasVmProtection
      puts "HA protected: #{runtime.dasVmProtection.dasProtected ? 'yes' : 'no'}"
    end
  end

  def self.ls_properties
    %w(name runtime.powerState runtime.connectionState)
  end
  
  def ls_text r
    out = ": #{r['runtime.powerState']}"
    if r['runtime.connectionState'] != 'connected'
      out = "#{out}, #{r['runtime.connectionState']}"
    end
    out
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
      'devices' => RVC::FakeFolder.new(self, :rvc_children_devices),
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

  def rvc_children_devices
    devices, = collect 'config.hardware.device'
    devices.each { |x| x.rvc_vm = self }
    Hash[devices.map { |x| [x.name, x] }]
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
