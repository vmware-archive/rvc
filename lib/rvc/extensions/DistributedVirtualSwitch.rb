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

class RbVmomi::VIM::DistributedVirtualSwitch
  field 'type' do
    summary 'Type of the object'
    block do
      ['vds']
    end
  end

  field 'hosts' do
    summary 'Host members of the vDS'
    property 'config'
    block do |config|
      hostnames = config.host.map { |host| host.config.host.name }
      size = hostnames.size
      if size > 10
        hostnames = hostnames[0..10]
        size -= 10
        hostnames << "(and #{size} more...)"
      end
      hostnames.join "\n"
    end
    default
  end

  field 'vlans' do
    summary 'VLANs in use by the vDS'
    property 'portgroup'
    block do |portgroups|
      trunk_ranges = []
      tag_ranges = []
      portgroups.each do |pg|
        vlan = pg.config.defaultPortConfig.vlan
        if vlan.class == VIM::VmwareDistributedVirtualSwitchVlanIdSpec
          if vlan.vlanId != 0
            tag_ranges << Range.new(vlan.vlanId,vlan.vlanId)
          end
        elsif vlan.class == VIM::VmwareDistributedVirtualSwitchTrunkVlanSpec
          vlan.vlanId.each { |range| trunk_ranges << Range.new(range.start,range.end) }
        end
      end
      trunks = $shell.cmds.vds.merge_ranges(trunk_ranges).map { |r|
        if r.begin == r.end then "#{r.begin}" else "#{r.begin}-#{r.end}" end
      }.join ','

      tags = $shell.cmds.vds.merge_ranges(tag_ranges).map { |r|
        if r.begin == r.end then "#{r.begin}" else "#{r.begin}-#{r.end}" end
      }.join ','
      str = ""
      if !trunk_ranges.empty?
        str += "#{trunks} (trunked)"
      end
      if !tag_ranges.empty?
        str += "\n#{tags} (switch tagged)\n"
      end
      str
    end
    default
  end

  field 'status' do
    default false
  end

  def display_info
    config, = collect(:config)
    puts "name: #{config.name}"
    puts "description: #{config.description}"
    puts "product: #{config.productInfo.vendor} #{config.productInfo.name} #{config.productInfo.version}"
    puts "ports: #{config.numPorts}"
    puts "standalone ports: #{config.numStandalonePorts}"
    puts "maximum ports: #{config.maxPorts}"
    puts "netIORM: #{config.networkResourceManagementEnabled}"
    puts "Default Port Configuration:"
    config.defaultPortConfig.dump_config self, "  ", false
  end

  def summarize
    t = table(['portgroup name', 'num ports', 'vlan', 'resource pool'])
    self.portgroup.each { |pg|
      if pg.config.defaultPortConfig
         respool = translate_respool self, pg.config.defaultPortConfig.networkResourcePoolKey
         vlan = pg.config.defaultPortConfig.vlan
      end

      if pg.config.defaultPortConfig
         t << [pg.config.name, pg.config.numPorts, translate_vlan(vlan), respool]
      else
         t << [pg.config.name, pg.config.numPorts, nil, nil]
      end
    }
    puts t
  end

  def portgroup_children
    portgroups = {}
    self.portgroup.each { |pg|
      portgroups[pg.name] = pg
    }
    portgroups
  end

  def respool_children
    respools = {}
    self.networkResourcePool.each do |pool|
      respools[pool.name] = pool
    end

    respools
  end

  def hosts_children
    hosts = {}
    self.config.host.each do |hostinfo|
      host = hostinfo.config.host
      hosts[host.collect(:name).first] = host
    end
    hosts
  end

  def children
    portgroups = RVC::FakeFolder.new(self, :portgroup_children)
    portgroups.define_singleton_method :display_info, lambda {
      vds = self.rvc_parent
      $shell.cmds.basic.table vds.portgroup, {}
    }

    {
      'portgroups' => portgroups,
      'respools' => RVC::FakeFolder.new(self, :respool_children),
      'hosts' => RVC::FakeFolder.new(self, :hosts_children),
    }
  end

  def ls_text r
    " (vds)"
  end

  def self.folder?
    true
  end
end
