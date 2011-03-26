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

  def children
    {
      'vms' => RVC::FakeFolder.new(self, :ls_vms),
      'datastores' => RVC::FakeFolder.new(self, :ls_datastores),
    }
  end

  def ls_vms
    RVC::Util.collect_children self, :vm
  end

  def ls_datastores
    RVC::Util.collect_children self, :datastore
  end
end
