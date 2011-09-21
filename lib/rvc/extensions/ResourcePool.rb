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

class RbVmomi::VIM::ResourcePool
  def self.ls_properties
    %w(name config.cpuAllocation config.memoryAllocation)
  end

  def ls_text r
    cpuAlloc, memAlloc = r['config.cpuAllocation'], r['config.memoryAllocation']

    cpu_shares_text = cpuAlloc.shares.level == 'custom' ? cpuAlloc.shares.shares.to_s : cpuAlloc.shares.level
    mem_shares_text = memAlloc.shares.level == 'custom' ? memAlloc.shares.shares.to_s : memAlloc.shares.level

    ": cpu %0.2f/%0.2f/%s, mem %0.2f/%0.2f/%s" % [
      cpuAlloc.reservation/1000.0, cpuAlloc.limit/1000.0, cpu_shares_text,
      memAlloc.reservation/1000.0, memAlloc.limit/1000.0, mem_shares_text,
    ]
  end

  def display_info
    cfg = config
    rt = runtime
    cpuAlloc, memAlloc = cfg.cpuAllocation, cfg.memoryAllocation


    cpu_shares_text = cpuAlloc.shares.level == 'custom' ? cpuAlloc.shares.shares.to_s : cpuAlloc.shares.level
    mem_shares_text = memAlloc.shares.level == 'custom' ? memAlloc.shares.shares.to_s : memAlloc.shares.level

    puts "cpu:"
    puts " reservation: %0.2f GHz" % [cpuAlloc.reservation/1e3]
    puts " limit: %0.2f GHz" % [cpuAlloc.limit/1e3]
    puts " shares: #{cpu_shares_text}"
    puts " usage: %0.2f Ghz (%0.1f)%%" % [rt.cpu.overallUsage/1e3, 100.0*rt.cpu.overallUsage/rt.cpu.maxUsage]
    puts "memory:"
    puts " reservation: %0.2f GB" % [memAlloc.reservation/1e3]
    puts " limit: %0.2f GB" % [memAlloc.limit/1e3]
    puts " shares: #{mem_shares_text}"
    puts " usage: %0.2f GB (%0.1f)%%" % [rt.memory.overallUsage/1e9, 100.0*rt.memory.overallUsage/rt.memory.maxUsage]
  end

  def children
    {
      'vms' => RVC::FakeFolder.new(self, :children_vms),
      'pools' => RVC::FakeFolder.new(self, :children_pools),
    }
  end

  def children_vms
    RVC::Util.collect_children self, :vm
  end

  def children_pools
    RVC::Util.collect_children self, :resourcePool
  end
end
