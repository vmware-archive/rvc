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

require "terminal-table/import"

opts :summarize do
  summary ""
  arg :obj, nil, :multi => false, :lookup => VIM::ManagedObject
end

def summarize obj
  if !obj.respond_to?(:summarize)
    puts "not a vds or portgroup!"
    return
  end
  obj.summarize
end

opts :create_portgroup do
  summary "Create a new potgroup on a vDS"
  arg :vds, nil, :lookup => VIM::DistributedVirtualSwitch
  arg :name, "Portgroup Name", :type => :string
  opt :num_ports, "Number of Ports", :type => :int
  opt :type, "Portgroup Type (i.e. 'earlyBinding', 'ephemeral', 'lateBinding'",
      :type => :string, :default => 'earlyBinding'
end

def create_portgroup vds, name, opts
  tasks [vds], :AddDVPortgroup, :spec => [{ :name => name,
                                            :type => opts[:type],
                                            :numPorts => opts[:numPorts] }]
end

opts :create do
  summary "Create a new vDS"
  arg :dest, "Destination", :lookup_parent => VIM::Folder
  opt :vds_version, "vDS version (i.e. '5.0.0', '4.1.0', '4.0.0')",
      :type => :string
end

def create dest, opts
  folder, name = *dest
  tasks [folder], :CreateDVS, :spec => { :configSpec => { :name => name },
                                         :productInfo => {
                                           :version => opts[:vds_version] } }
end

def get_inherited_config obj
  if obj.is_a?(VIM::DistributedVirtualSwitch)
    nil
  elsif obj.is_a?(VIM::DistributedVirtualPortgroup)
    obj.config.distributedVirtualSwitch.config.defaultPortConfig
  elsif obj.is_a?(VIM::DistributedVirtualPort)
    obj.rvc_parent.config.defaultPortConfig
  end
end

def apply_settings obj, port_spec
  if obj.is_a?(VIM::DistributedVirtualSwitch)
    tasks [obj], :ReconfigureDvs, :spec => { :defaultPortConfig => port_spec }
  elsif obj.is_a?(VIM::DistributedVirtualPortgroup)
    vds = obj.config.distributedVirtualSwitch
    collapse_inheritance vds.config.defaultPortConfig, port_spec
    tasks [obj], :ReconfigureDVPortgroup,
                 :spec => { :defaultPortConfig => port_spec,
                            :configVersion => obj.config.configVersion}
  elsif obj.is_a?(VIM::DistributedVirtualPort)
    config = obj.rvc_parent.config
    vds = config.distributedVirtualSwitch
    collapse_inheritance config.defaultPortConfig, port_spec
    tasks [vds], :ReconfigureDVPort, :port => [{ :key => obj.key,
                                                 :operation => 'edit',
                                                 :setting => port_spec }]
  end
end


def collapse_inheritance default_spec, port_spec
  inherited = true
  if port_spec.is_a? Hash
    port_spec.keys.each do |key|
      if key == :inherited then next end
      default_child = default_spec.send key
      child = port_spec[key]
      child_inheritance = collapse_inheritance default_child, child
      inherited = inherited && child_inheritance
    end
    if port_spec.has_key?(:inherited)
      port_spec[:inherited] = inherited
    end
    inherited
  else
    if default_spec == port_spec
      true
    else
      false
    end
  end
end


opts :shaper do
  summary "Configure a traffic shaping on a vDS or portgroup"
  arg :obj, nil,
      :lookup => [VIM::DistributedVirtualPort,
                  VIM::DistributedVirtualPortgroup,
                  VIM::DistributedVirtualSwitch]
  opt :tx, "Apply Settings for Tx Shaping", :type => :bool
  opt :rx, "Apply Settings for Rx Shaping", :type => :bool
  opt :enable, "Enable Traffic Shaping", :type => :bool
  opt :disable, "Disable Traffic Shaping", :type => :bool
  opt :average_bw, "Average Bandwith in kilobits per second", :type => :int
  opt :burst_size, "Maximum burst size allowed in kilobytes", :type => :int
  opt :peak_bw, "Peak bandwidth during bursts in kilobits per second", :type => :int
end

def shaper obj, opts
  if !(opts[:tx] or opts[:rx]) or (opts[:tx] and opts[:rx])
    puts "Need to configure either Rx or Tx Shaping!"
    return
  end

  if opts[:enable] and opts[:disable]
    puts "Can't both enable and disable traffic shaping!"
    return
  end

  shaper_spec = { :inherited => false}
  if opts[:enable]
    shaper_spec[:enabled] = { :value => true, :inherited => false }
  end
  if opts[:disable]
    shaper_spec[:enabled] = { :value => false, :inherited => false }
  end

  if opts[:average_bw]
    shaper_spec[:averageBandwidth] = { :value => (opts[:average_bw] * 1000),
                                       :inherited => false }
  end

  if opts[:burst_size]
    shaper_spec[:burstSize] = { :value => (opts[:burst_size] * 1000),
                                :inherited => false }
  end

  if opts[:peak_bw]
    shaper_spec[:peakBandwidth] = { :value => (opts[:peak_bw] * 1000),
                                    :inherited => false }
  end

  if opts[:rx]
    port_spec = { :inShapingPolicy => shaper_spec }
  else
    port_spec = { :outShapingPolicy => shaper_spec }
  end

  apply_settings obj, port_spec
end

opts :block do
  summary "Block traffic on a vDS, portgroup, or port"
  arg :obj, nil,
      :lookup => [VIM::DistributedVirtualPort,
                  VIM::DistributedVirtualPortgroup,
                  VIM::DistributedVirtualSwitch]
end

def block obj
  apply_settings obj, { :blocked => { :value => true, :inherited => false } }
end

opts :unblock do
  summary "Unblock traffic on a vDS, portgroup, or port"
  arg :obj, nil,
      :lookup => [VIM::DistributedVirtualPort,
                  VIM::DistributedVirtualPortgroup,
                  VIM::DistributedVirtualSwitch]
end

def unblock obj
  apply_settings obj, { :blocked => { :value => false, :inherited => false } }
end

# XXX pvlan?
opts :vlan_trunk do
  summary "Configure a VLAN range on a vDS or portgroup to be trunked"
  arg :obj, nil,
      :lookup => [VIM::DistributedVirtualPort,
                  VIM::DistributedVirtualPortgroup,
                  VIM::DistributedVirtualSwitch]
  arg :vlan, "VLAN Configuration (i.e. '1000-2000', '2012', '2012,3013', '1000-2000,2012')", :type => :string
  opt :append, "Append new VLAN settings to configuration, rather than replacing the existing settings", :type => :bool
  opt :exclude, "Remove a specific range of VLAN settings from configuration. ", :type => :bool
end

def vlan_trunk obj, vlan, opts
  ranges = []
  vlan.sub(' ', '').split(',').each do |range_str|
    range_val = range_str.split('-')
    ranges << Range.new(range_val[0].to_i,
                        if range_val.length > 1
                          range_val[1].to_i
                        else
                          range_val[0].to_i
                        end)
  end

  if opts[:append] or opts[:exclude]
    old_vlan = obj.config.defaultPortConfig.vlan
    if old_vlan.class == VIM::VmwareDistributedVirtualSwitchVlanIdSpec
      puts "Can't append/exclude trunk range to switch tagging configuration!"
      return
    elsif old_vlan.class == VIM::VmwareDistributedVirtualSwitchTrunkVlanSpec
      old_vlan = old_vlan.vlanId.map { |r| r.start..r.end }
    end
    old_vlan = merge_ranges(old_vlan)
  end

  if opts[:append]
    ranges = ranges + old_vlan
  end

  ranges = merge_ranges(ranges)

  if opts[:exclude]
    ranges = subtract_ranges(old_vlan, ranges)
    ranges = merge_ranges(ranges)
  end

  spec = VIM::VMwareDVSPortSetting.new()
  spec.vlan = VIM::VmwareDistributedVirtualSwitchTrunkVlanSpec.new()
  spec.vlan.vlanId = ranges.map { |r| { :start => r.first, :end => r.last } }
  spec.vlan.inherited = false

  if ranges.empty?
    # if we excluded all ranges, just allow everything
    vlan_switchtag obj, 0
    return
  end

  inherited_spec = get_inherited_config(obj)
  if inherited_spec != nil then inherited_spec = inherited_spec.vlan end

  if inherited_spec.class == VIM::VmwareDistributedVirtualSwitchTrunkVlanSpec
    inherited_ranges = inherited.vlanId.map { |range| range.start..range.end }
    if (merge_ranges(inherited_ranges) - ranges) == []
      spec.vlan.inherited = true
    end
  end

  apply_settings obj, spec
end

opts :vlan_switchtag do
  summary "Configure a VLAN on a vDS or portgroup for vSwitch tagging"
  arg :obj, nil,
      :lookup => [VIM::DistributedVirtualPort,
                  VIM::DistributedVirtualPortgroup,
                  VIM::DistributedVirtualSwitch]
  arg :vlan, "VLAN id", :type => :int
end

def vlan_switchtag obj, vlan
  # if it matches, inherit settings from switch or portgroup
  inherited = false
  inherited_spec = get_inherited_config(obj)
  if inherited_spec != nil then inherited_spec = inherited_spec.vlan end

  if inherited_spec.class == VIM::VmwareDistributedVirtualSwitchVlanIdSpec
    if inherited_spec.vlanId.to_s == vlan.to_s
      inherited = true
    end
  end

  spec = VIM::VMwareDVSPortSetting.new()
  spec.vlan = VIM::VmwareDistributedVirtualSwitchVlanIdSpec.new()
  spec.vlan.vlanId = vlan
  spec.vlan.inherited = inherited
  apply_settings obj, spec
end

def merge_ranges(ranges)
  ranges = ranges.sort_by {|r| r.first }
  if !ranges.empty?
    *outages = ranges.shift
  else
    outages = []
  end
  ranges.each do |r|
    lastr = outages[-1]
    if lastr.last >= r.first - 1
      outages[-1] = lastr.first..[r.last, lastr.last].max
    else
      outages.push(r)
    end
  end
  outages
end


def subtract_ranges(ranges, minus_ranges)
  outages = []
  minus_range = minus_ranges.shift
  ranges.each do |r|
    while true
      if minus_range == nil or (minus_range.first > r.last)
        break
      elsif minus_range.first < r.first and minus_range.last < r.first
        next
      elsif minus_range.first <= r.first and minus_range.last < r.last
        r = ((minus_range.last+1)..r.last)
        minus_range = minus_ranges.shift
        next
      elsif minus_range.first > r.first and minus_range.last >= r.last
        r = (r.first..(minus_range.first-1))
        break
      elsif minus_range.first > r.first and minus_range.last < r.last
        outages << (r.first..(minus_range.first-1))
        r = ((minus_range.last+1)..r.last)
        minus_range = minus_ranges.shift
        break
      elsif minus_range.first <= r.first and minus_range.last >= r.last
        if minus_range.last == r.last
          minus_range = minus_ranges.shift
        end
        r = nil
        break
      end
    end
    if r != nil
      outages << r
    end
  end
  outages
end


opts :security do
  summary "Configure a security settings on a vDS or portgroup"
  arg :obj, nil,
      :lookup => [VIM::DistributedVirtualPort,
                  VIM::DistributedVirtualPortgroup,
                  VIM::DistributedVirtualSwitch]
  opt :allow_promisc, "Allow VMs to enter promiscuous mode", :type => :bool
  opt :deny_promisc,  "Prevent VMs from entering promiscuous mode", :type => :bool
  opt :allow_mac_changes, "Allow VMs to change their MAC addresses from within the Guest OS.", :type => :bool
  opt :deny_mac_changes, "Prevent VMs from changing their MAC addresses from within the Guest OS.", :type => :bool
  opt :allow_forged, "Allow VMs to transmit packets originating from other MAC addresses", :type => :bool
  opt :deny_forged, "Prevent VMs from transmitting packets originating from other MAC addresses", :type => :bool
end

def security obj, opts
  if (opts[:allow_promisc] and opts[:deny_promisc]) or
      (opts[:allow_mac_changes] and opts[:deny_mac_changes]) or
      (opts[:allow_forged] and opts[:deny_forged])
    puts "Can't both allow and deny!"
    return
  end

  policy = { :inherited => false }
  if opts[:allow_promisc]
    policy[:allowPromiscuous] = { :inherited => false, :value => true }
  elsif opts[:deny_promisc]
    policy[:allowPromiscuous] = { :inherited => false, :value => false }
  end

  if opts[:allow_mac_changes]
    policy[:macChanges] = { :inherited => false, :value => true }
  elsif opts[:deny_mac_changes]
    policy[:macChanges] = { :inherited => false, :value => false }
  end

  if opts[:allow_forged]
    policy[:forgedTransmits] = { :inherited => false, :value => true }
  elsif opts[:deny_forged]
    policy[:forgedTransmits] = { :inherited => false, :value => false }
  end

  inherited_spec = get_inherited_config(obj)
  if inherited_spec != nil
    collapse_inheritance inherited_spec.securityPolicy, policy
  end

  spec = VIM::VMwareDVSPortSetting.new()
  spec.securityPolicy = policy

  apply_settings obj, spec
end

opts :unset_respool do
  summary "Remove vDS portgroup or port from a network resource pool"
  arg :obj, nil,
      :lookup => [VIM::DistributedVirtualPort,
                  VIM::DistributedVirtualPortgroup]
end

def unset_respool obj
  apply_settings obj, {:networkResourcePoolKey => {:inherited => false,
                                                   :value => nil} }
end

opts :set_respool do
  summary "Remove vDS portgroup or port from a network resource pool"
  arg :obj, nil,
      :lookup => [VIM::DistributedVirtualPort,
                  VIM::DistributedVirtualPortgroup]
  arg :respool, nil, :lookup => [VIM::DVSNetworkResourcePool]
end

def set_respool obj, respool
  apply_settings obj, {:networkResourcePoolKey => {:inherited => false,
                                                   :value => respool.key} }
end
