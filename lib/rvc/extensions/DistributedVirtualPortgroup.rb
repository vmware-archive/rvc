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

class RbVmomi::VIM::DistributedVirtualPortgroup
  def summarize
    vds = self.config.distributedVirtualSwitch
    pc = vds._connection.propertyCollector
    ports = vds.FetchDVPorts(:criteria => {
                               :portgroupKey => [self.key], :inside => true,
                               :active => true})

    if ports.empty?
      puts "No active ports in portgroup"
      return
    end

    objects = []
    ports.each { |port|
      objects << port.proxyHost
      objects << port.connectee.connectedEntity
    }

    spec = {
      :objectSet => objects.map { |obj| { :obj => obj } },
      :propSet => [{:type => "ManagedEntity", :pathSet => %w(name) }]
    }

    props = pc.RetrieveProperties(:specSet => [spec])
    t = table(['key', 'name', 'vlan', 'blocked', 'host', 'connectee'])
    data = []

    names = {}
    props.each { |prop| names[prop.obj] = prop['name'] }
    ports.each { |port|
      port_key = begin port.key.to_i; rescue port.key; end
      # XXX map resource pools, vlan config properly
      data << [port_key, port.config.name,
      #puts [port_key, port.config.name,
               translate_vlan(port.config.setting.vlan),
               port.state.runtimeInfo.blocked,
               names[port.proxyHost],
               #port.config.setting.networkResourcePoolKey.value,
               "#{names[port.connectee.connectedEntity]}"]
    }
    data.sort { |x,y| x[0] <=> y[0] }.each { |row| t << row }
    puts t
  end

  def display_info
    vds = self.config.distributedVirtualSwitch
    self.config.defaultPortConfig.dump_config vds, ""
  end


  def self.folder?
    true
  end

  def children
    vds = self.config.distributedVirtualSwitch

    ports = vds.FetchDVPorts(:criteria => {:portgroupKey => [self.key],
                               :inside => true, :active => true})
    children = {}
    begin
      # try to sort port keys in numeric order
      keys = ports.map {|port| [port.key.to_i, port]}.sort {|x,y| x[0] <=> y[0]}
    rescue
      keys = ports.map { |port| port.key }
    end
    keys.each { |i| children["port-#{i[0]}"] = i[1] }
    children['all'] = RVC::FakeFolder.new(self, :get_all_ports)

    children
  end

  def traverse_one arc
    if arc == 'all'
      RVC::FakeFolder.new(self, :get_all_ports)
    else
      port_num = arc.gsub(/^port-/, '').to_i
      vds = self.config.distributedVirtualSwitch
      ports = vds.FetchDVPorts(:criteria => {:portKey => [port_num.to_s]})
      return ports[0]
    end
  end

  def rvc_ls
    children = self.children
    name_map = children.invert
    children, fake_children = children.partition { |k,v| v.is_a? VIM::ManagedEntity }
    i = 0

    pc = self.config.distributedVirtualSwitch._connection.propertyCollector

    objects = []
    fake_children.each do |name, port|
      if port.respond_to?(:connectee)
        objects << port.connectee.connectedEntity
      end
    end

    if objects.any? { |x| x.is_a? VIM::VirtualMachine }
      spec = {
        :objectSet => objects.map { |obj| { :obj => obj } },
        :propSet => [{:type => "VirtualMachine",
                       :pathSet => %w(guest.net config.hardware.device name)}]
      }

      prop_sets = pc.RetrieveProperties(:specSet => [spec])
    else
      prop_sets = []
    end

    #pp prop_sets

    ips = {}
    macs = {}
    device_macs = {}
    names = {}
    prop_sets.each do |prop_set|
      prop_set.propSet.each do |prop|
        if prop.name == "guest.net"
          prop.val.each do |nicinfo|
            #XXX nicinfo.ipConfig has more info and IPv6
            ips[prop_set.obj.to_s +
                nicinfo.deviceConfigId.to_s] = nicinfo.ipAddress
            macs[prop_set.obj.to_s +
                 nicinfo.deviceConfigId.to_s] = nicinfo.macAddress
          end
        elsif prop.name == "config.hardware.device"
          prop.val.each do |device|
            if device.class < VIM::VirtualEthernetCard
              device_macs[prop_set.obj.to_s +
                          device.key.to_s] = device.macAddress
            end
          end
        elsif prop.name == "name"
          names[prop_set.obj] = prop.val
        end
      end
    end
    #pp ip
    #pp mac
    #pp device_mac

    fake_children.each do |name,child|
      print "#{i} #{name}"
      if child.class.folder?
        print "/"
      end
      if child.respond_to?(:connectee)
        vm_name = names[child.connectee.connectedEntity]
        mac = macs[child.connectee.connectedEntity.to_s +
                   child.connectee.nicKey]
        ip = ips[child.connectee.connectedEntity.to_s + child.connectee.nicKey]
        device_mac = device_macs[child.connectee.connectedEntity.to_s +
                                 child.connectee.nicKey]
        if mac and ip
          puts " (#{mac} #{ip} #{vm_name})"
        elsif device_mac
          puts " (#{device_mac} #{vm_name})"
        else
          puts ""
        end
      else
        puts ""
      end
      child.rvc_link self, name
      CMD.mark.mark i.to_s, [child]
      i += 1
    end
  end

  def get_all_ports
    hash = {}
    vds = self.config.distributedVirtualSwitch
    begin
      keys = self.portKeys.map { |key| key.to_i }.sort
    rescue
      keys = self.portKeys
    end
    keys.each { |key| hash["port-#{key}"] = LazyDVPort.new(self, key) }
    hash
  end
end

#XXX can we use a lazy delegate but not fetch the object during `ls`?
class LazyDVPort
  include RVC::InventoryObject

  def initialize(pg, key)
    @pg = pg
    @key = key
  end

  def get_real_port
    @port ||= @pg.config.distributedVirtualSwitch.FetchDVPorts(:criteria => {:portKey => [@key]})[0]
  end

  def display_info
    self.get_real_port.display_info
  end
end

def translate_vlan vlan
  case "#{vlan.class}"
  when "VmwareDistributedVirtualSwitchVlanIdSpec"
    config = vlan.vlanId == 0 ? "-" : vlan.vlanId.to_s + " (switch tagging)"
  when "VmwareDistributedVirtualSwitchTrunkVlanSpec"
    config = vlan.vlanId.map { |r|
      if r.start != r.end
        "#{r.start}-#{r.end}"
      else
        "#{r.start}"
      end
    }.join(',') + " (trunked)"
  when "Array"
    config = vlan.map { |r|
      if r.start != r.end
        "#{r.start}-#{r.end}"
      else
        "#{r.start}"
      end
    }.join(',')
    if config == "0"
      config = "-"
    else
      config += " (trunked)"
    end
  when "VmwareDistributedVirtualSwitchPvlanSpec"
    # XXX needs to be mapped
    config = vlan.pvlanId.to_s + " (pvlan?)"
  end

  config
end

def translate_respool vds, pk, show_inheritance = true
  if pk.value == '-1'
    poolName = "-"
  else
    poolName = vds.networkResourcePool.find_all { |pool|
      pk.value == pool.key
    }[0].name
  end

  if show_inheritance and !pk.inherited
    poolName += "*"
  end
  poolName
end
