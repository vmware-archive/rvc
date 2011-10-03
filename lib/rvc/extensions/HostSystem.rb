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

class RbVmomi::VIM::HostSystem
  def self.ls_properties
    %w(name summary.hardware.memorySize summary.hardware.cpuModel
       summary.hardware.cpuMhz summary.hardware.numCpuPkgs
       summary.hardware.numCpuCores summary.hardware.numCpuThreads)
  end

  def ls_text r
    memorySize, cpuModel, cpuMhz, numCpuPkgs, numCpuCores =
      %w(memorySize cpuModel cpuMhz numCpuPkgs numCpuCores).map { |x| r["summary.hardware.#{x}"] }
    " (host): cpu #{numCpuPkgs}*#{numCpuCores}*#{"%.2f" % (cpuMhz.to_f/1000)} GHz, memory #{"%.2f" % (memorySize/10**9)} GB"
  end

  def display_info
    summary = self.summary
    runtime = summary.runtime
    stats = summary.quickStats
    hw = summary.hardware
    puts "connection state: #{runtime.connectionState}"
    puts "power state: #{runtime.powerState}"
    puts "uptime: #{"%0.2f" % ((Time.now - runtime.bootTime)/(24*3600))} days" if runtime.bootTime
    puts "in maintenance mode: #{runtime.inMaintenanceMode}"
    puts "standby mode: #{runtime.standbyMode}" if runtime.standbyMode
    if about = summary.config.product
      puts "product: #{about.fullName}"
      puts "license: #{about.licenseProductName} #{about.licenseProductVersion}" if about.licenseProductName
    end
    overallCpu = hw.numCpuPkgs * hw.numCpuCores * hw.cpuMhz
    puts "cpu: %d*%d*%.2f GHz = %.2f GHz" % [hw.numCpuPkgs, hw.numCpuCores, hw.cpuMhz/1e3, overallCpu/1e3]
    puts "cpu usage: %.2f GHz (%.1f%%)" % [stats.overallCpuUsage/1e3, 100*stats.overallCpuUsage/overallCpu]
    puts "memory: %.2f GB" % [hw.memorySize/1e9]
    puts "memory usage: %.2f GB (%.1f%%)" % [stats.overallMemoryUsage/1e3, 100*1e6*stats.overallMemoryUsage/hw.memorySize]
  end

  def children
    lazy_esxcli = esxcli
    {
      'vms' => RVC::FakeFolder.new(self, :ls_vms),
      'datastores' => RVC::FakeFolder.new(self, :ls_datastores),
      'esxcli' => lazy_esxcli,
    }
  end

  def ls_vms
    RVC::Util.collect_children self, :vm
  end

  def ls_datastores
    RVC::Util.collect_children self, :datastore
  end
end

class VIM::EsxcliNamespace
  include RVC::InventoryObject

  def ls_text r
    "/"
  end

  def children
    @namespaces.merge(Hash[@commands.map { |k,v| [k, RVC::EsxcliMethod.new(self, v)] }])
  end
end

class RVC::EsxcliMethod
  include RVC::InventoryObject
  attr_reader :ns, :info

  def initialize ns, info
    @ns = ns
    @info = info
  end

  def ls_text r
    ""
  end
end
