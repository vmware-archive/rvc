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
    # if possible, get info about the connected VM
    vm_name = ""
    mac = ""
    ip = ""
    if self.connectee
      vm = self.connectee.connectedEntity
      if vm.class == VIM::VirtualMachine
        vm_name = vm.name
        mac = vm.config.hardware.device.reject { |device|
          !(device.class < VIM::VirtualEthernetCard &&
            device.key.to_s == self.connectee.nicKey)
        }.first.macAddress
        nicinfo = vm.guest.net.reject { |info|
          info.deviceConfigId.to_s != self.connectee.nicKey.to_s
        }.first

        if nicinfo != nil
          ip = nicinfo.ipAddress
          if nicinfo.macAddress != nil and nicinfo.macAddress != ""
            mac = nicinfo.macAddress
          end
        end
      end
    end

    # if possible, get info about the port configuration
    poolName = "-"
    vlan = "-"
    link_up = false
    if self.state.runtimeInfo
      vds = self.rvc_parent.config.distributedVirtualSwitch
      poolName = translate_respool vds, self.config.setting.networkResourcePoolKey
      vlan = translate_vlan self.state.runtimeInfo.vlanIds
      link_up = self.state.runtimeInfo.linkUp
    end


    #puts "name: #{self.config.name}"
    puts_policy "blocked:", self.config.setting.blocked
    puts        "link up: #{link_up}"
    #puts       "vds: #{vds.name}"
    #puts       "portgroup: #{self.rvc_parent.name}"
    puts        "vlan: #{vlan}"
    puts        "network resource pool: #{poolName}"
    puts        "name: #{self.config.name}"
    puts        "description: #{self.config.description}"
    puts        "host: #{if self.proxyHost then self.proxyHost.name end}"
    puts        "vm: #{vm_name}"
    puts        "mac: #{mac}"
    puts        "ip: #{ip}"
    #XXX scope?
    setting = self.config.setting
    puts        "Rx Shaper:"
    policy = setting.inShapingPolicy
    puts_policy "  enabled:", policy.enabled
    puts_policy("  average bw:", policy.averageBandwidth, "b/sec"){|v|metric(v)}
    puts_policy("  peak bw:", policy.peakBandwidth, "b/sec") { |v| metric(v) }
    puts_policy("  burst size:", policy.burstSize, "B") { |v| metric(v) }
    puts        "Tx Shaper:"
    policy = setting.inShapingPolicy
    puts_policy "  enabled:", policy.enabled
    puts_policy("  average bw:", policy.averageBandwidth, "b/sec"){|v|metric(v)}
    puts_policy("  peak bw:", policy.peakBandwidth, "b/sec") { |v| metric(v) }
    puts_policy("  burst size:", policy.burstSize, "B") { |v| metric(v) }
    puts_policy "enable ipfix monitoring:", self.config.setting.ipfixEnabled
    puts_policy "forward all tx to uplink:", self.config.setting.txUplink
    if self.state
      if self.state.stats
        puts "Statistics:"
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
          puts "  #{stat}: #{num}"
        }
      end
    end
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
