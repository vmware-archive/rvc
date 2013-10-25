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

class RbVmomi::VIM::ClusterComputeResource
  def self.ls_properties
    %w(name summary.effectiveCpu summary.effectiveMemory)
  end

  def ls_text r
    " (cluster): cpu #{r['summary.effectiveCpu']/1000} GHz, memory #{r['summary.effectiveMemory']/1000} GB"
  end

  # TODO add datastore, network
  def children
    hosts, resourcePool = collect *%w(host resourcePool)
    {
      'hosts' => RVC::FakeFolder.new(self, :rvc_host_children),
      'resourcePool' => resourcePool,
    }
  end

  def rvc_host_children
    RVC::Util.collect_children self, :host
  end

  def display_info
    super
    pc = _connection.serviceContent.propertyCollector
    cfg, = collect 'configurationEx'
    drs = cfg.drsConfig
    ha = cfg.dasConfig
    puts "DRS: #{drs.enabled ? drs.defaultVmBehavior : 'disabled'}"
    puts "HA: #{ha.enabled ? 'enabled' : 'disabled'}"
    puts "VM Swap Placement: #{cfg.vmSwapPlacement}"
  end
end
