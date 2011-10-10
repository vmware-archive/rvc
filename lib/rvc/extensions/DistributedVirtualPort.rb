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

class RbVmomi::VIM::DistributedVirtualPort
  include RVC::InventoryObject

  def display_info
    puts "name: #{self.config.name}"
    puts "description: #{self.config.description}"
    puts "host: #{if self.proxyHost then self.proxyHost.name end}"
    puts "vds: #{self.dvsUuid}" #XXX map name
    puts "portgroup: #{self.portgroupKey}" #XXX map name
    #XXX scope?
    puts "Settings:"
    puts "  blocked: #{self.config.setting.blocked.value}"
    puts "  Rx Shaper:"
    policy = self.config.setting.inShapingPolicy
    puts "    enabled: #{policy.enabled.value}"
    puts "    average bw: #{metric(policy.averageBandwidth.value)}b/sec"
    puts "    peak bw: #{metric(policy.peakBandwidth.value)}b/sec"
    puts "    burst size: #{metric(policy.burstSize.value)}B"
    puts "  Tx Shaper:"
    policy = self.config.setting.inShapingPolicy
    puts "    enabled: #{policy.enabled.value}"
    puts "    average bw: #{metric(policy.averageBandwidth.value)}b/sec"
    puts "    peak bw: #{metric(policy.peakBandwidth.value)}b/sec"
    puts "    burst size: #{metric(policy.burstSize.value)}B"
    puts "Connectee:"
    conectee = self.connectee
    if connectee
      puts "  address hint: #{self.connectee.addressHint}"
      puts "  connected entity: #{self.connectee.connectedEntity.name}"
      puts "  nic key: #{self.connectee.nicKey}" #XXX map name?
      puts "  type: #{self.connectee.type}"
    end
    puts "State:" #XXX
    if self.state
      if self.state.runtimeInfo
        ri = self.state.runtimeInfo
        puts "  link up: #{ri.linkUp}"
        puts "  blocked: #{ri.blocked}"
        puts "  vlan ids: #{ri.vlanIds}" #XXX map to something reasonable
        puts "  trunk mode: #{ri.trunkingMode}"
        puts "  mtu: #{ri.mtu}"
        puts "  link peer: #{ri.linkPeer}"
        puts "  mac address: #{ri.macAddress}"
        puts "  status detail: #{ri.statusDetail}"
      end
      if self.state.stats
        puts "  Statistics:"
        stats = self.state.stats
        # normally, i would explicitly write this out, but in this case
        # the stats are pretty self explanatory, and require pretty much
        # no formatting, so we just procedurally generate them
        stats.class.full_props_desc.map { |stat|
          stat = stat['name']
          num = stats.send(stat)
          # skip uninteresting properties
          if !num.is_a?(Integer) then next end
          # un-camelcase the name of the stat
          stat = stat.gsub(/[A-Z]/) { |p| ' ' + p.downcase}
          puts "    #{stat}: #{num}"
        }
      end
    end
  end

  #def self.ls_properties
  #  #%w(connectee.connectedEntity.config.name
  #end

  def ls_text r
    #XXX reading every VM name is slow and maybe not a great idea?
    #" (#{self.proxyHost.name})"
    " (#{self.connectee.connectedEntity.config.name} - #{self.proxyHost.name})"
  end

  def self.folder?
    true
  end

  def children
    {
      'vm' => self.connectee.connectedEntity,
      'host' => self.proxyHost
    }
  end
end
