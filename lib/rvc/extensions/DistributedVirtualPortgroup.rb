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
    ports = vds.FetchDVPorts(:criteria => {:inside => true, :active => true})

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
               nil, #port.config.setting.vlan.vlanId,#.map { |r| "#{r.start}-#{r.end}" }.join(','),
               port.state.runtimeInfo.blocked,
               names[port.proxyHost],
               #port.config.setting.networkResourcePoolKey.value,
               "#{names[port.connectee.connectedEntity]}"]
    }
    data.sort { |x,y| x[0] <=> y[0] }.each { |row| t << row }
    puts t
  end

  def display_info
    # we really just want to show the default port configuration
    config = self.config.defaultPortConfig
    vds = self.config.distributedVirtualSwitch

    # map network respool to human-readable name
    poolkey = config.networkResourcePoolKey.value
    if poolkey == '-1'
      poolName = "-"
    else
      poolName = vds.networkResourcePool.find_all { |pool|
        poolkey == pool.key
      }[0].name
    end

    # translate vlan value
    vlan = 0
    case "#{config.vlan.class}"
      when "VmwareDistributedVirtualSwitchVlanIdSpec"
      vlan = config.vlan.vlanId
      when "VmwareDistributedVirtualSwitchTrunkVlanSpec"
      vlan = config.vlan.vlanId.map { |r| "#{r.start}-#{r.end}" }.join(',')
      when "VmwareDistributedVirtualSwitchPvlanSpec"
      # XXX needs to be mapped
      vlan = pvlanId
    end
    if vlan == 0 then vlan = '-' end


    puts "blocked: #{config.blocked.value}"
    puts "vlan: #{vlan}"
    puts "network resource pool: #{poolName}"
    puts "Rx Shaper: "
    policy = config.inShapingPolicy
    puts "  enabled: #{policy.enabled.value}"
    puts "  average bw: #{metric(policy.averageBandwidth.value)}b/sec"
    puts "  peak bw: #{metric(policy.peakBandwidth.value)}b/sec"
    puts "  burst size: #{metric(policy.burstSize.value)}B"
    puts "Tx Shaper:"
    policy = config.outShapingPolicy
    puts "  enabled: #{policy.enabled.value}"
    puts "  average bw: #{metric(policy.averageBandwidth.value)}b/sec"
    puts "  peak bw: #{metric(policy.peakBandwidth.value)}b/sec"
    puts "  burst size: #{metric(policy.burstSize.value)}B"
    puts "Uplink Teaming Policy:"
    policy = config.uplinkTeamingPolicy
    puts "  policy: #{policy.policy.value}" #XXX map the strings values
    puts "  reverse policy: #{policy.reversePolicy.value}"
    puts "  notify switches: #{policy.notifySwitches.value}"
    puts "  rolling order: #{policy.rollingOrder.value}"
    puts "  Failure Criteria: "
    criteria = policy.failureCriteria
    puts "    check speed: #{criteria.checkSpeed.value}"
    puts "    speed: #{metric(criteria.speed.value)}Mb/sec"
    puts "    check duplex: #{criteria.checkDuplex.value}"
    puts "    full duplex: #{criteria.fullDuplex.value}"
    puts "    check error percentage: #{criteria.checkErrorPercent.value}"
    puts "    max error percentage: #{criteria.percentage.value}%"
    puts "    check beacon: #{criteria.checkBeacon.value}"
    puts "  Uplink Port Order:"
    order = policy.uplinkPortOrder
    puts "    active: #{order.activeUplinkPort.join(',')}"
    puts "    standby: #{order.standbyUplinkPort.join(',')}"
    puts "Security:"
    policy = config.securityPolicy
    puts "  allow promiscuous mode: #{policy.allowPromiscuous.value}"
    puts "  allow mac changes: #{policy.macChanges.value}"
    puts "  allow forged transmits: #{policy.forgedTransmits.value}"
    puts "ipfixEnabled: #{config.ipfixEnabled.value}"
    puts "txUplink: #{config.txUplink.value}"
  end


  def self.folder?
    true
  end

  def children
    vds = self.config.distributedVirtualSwitch

    ports = vds.FetchDVPorts(:criteria => {:portgroupKey => [self.key],
                               :inside => true, :active => true})

    children = {}

    #begin
    # try to sort port keys in numeric order
    keys = ports.map { |port| [port.key.to_i, port]}.sort { |x,y| x[0] <=> y[0] }.each { |i| children["port-#{i[0]}"] = i[1] }
    #XXX (handle case if port keys are not numeric
    #rescue
    #  keys = ports.map { |port| port.key }
    #end
    children['all'] = RVC::FakeFolder.new(self, :get_all_ports)

    children
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

def metric num
  if num > 1000000000000
    (num / 1000000000000).to_s + 'T'
  elsif num > 1000000000
    (num / 1000000000).to_s + 'G'
  elsif num > 1000000
    (num / 1000000).to_s + 'M'
  elsif num > 1000
    (num / 1000).to_s + 'K'
  else
    num.to_s
  end
end
