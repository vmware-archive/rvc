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
      respool = translate_respool self, pg.config.defaultPortConfig.networkResourcePoolKey
      vlan = pg.config.defaultPortConfig.vlan

      t << [pg.config.name, pg.config.numPorts, translate_vlan(vlan), respool]
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
    {
      'portgroups' => RVC::FakeFolder.new(self, :portgroup_children),
      'respools' => RVC::FakeFolder.new(self, :respool_children),
      'hosts' => RVC::FakeFolder.new(self, :hosts_children),
    }
  end

  def ls_text r
    " (vds)"
  end
end
