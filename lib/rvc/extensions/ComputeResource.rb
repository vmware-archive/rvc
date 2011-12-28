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

class RbVmomi::VIM::ComputeResource
  # TODO expand, optimize
  def display_info
    pc = _connection.serviceContent.propertyCollector
    name, host = collect 'name', 'host'
    stats = self.stats
    pct_cpu_used = 100.0*stats[:usedCPU]/stats[:totalCPU]
    pct_mem_used = 100.0*stats[:usedMem]/stats[:totalMem]
    puts "name: #{name}"
    puts "cpu: #{stats[:totalCPU]/1e3} GHz (#{pct_cpu_used.to_i}% used)"
    puts "memory: #{stats[:totalMem]/1e3} GB (#{pct_mem_used.to_i}% used)"

    host_names = pc.collectMultiple host, 'name'
    puts "hosts:"
    host.each do |h|
      puts " #{host_names[h]['name']}"
    end
  end

  def self.ls_properties
    %w(name summary.effectiveCpu summary.effectiveMemory)
  end

  def ls_text r
    " (standalone): cpu #{r['summary.effectiveCpu']/1000} GHz, memory #{r['summary.effectiveMemory']/1000} GB"
  end

  # TODO add datastore, network
  def children
    hosts, resourcePool = collect *%w(host resourcePool)
    {
      'host' => hosts[0],
      'resourcePool' => resourcePool,
    }
  end
end
