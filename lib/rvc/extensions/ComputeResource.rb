# Copyright (c) 2011 VMware, Inc.  All Rights Reserved.

class RbVmomi::VIM::ComputeResource
  # TODO expand, optimize
  def display_info
    puts "name: #{name}"
    puts "hosts:"
    host.each do |h|
      puts " #{h.name}"
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
