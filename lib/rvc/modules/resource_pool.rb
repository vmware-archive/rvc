# Copyright (c) 2011 VMware, Inc.  All Rights Reserved.

opts :create do
  summary "Create a resource pool"
  arg :name, "Name of the new resource pool."
  arg :parent, nil, :lookup => RbVmomi::VIM::ResourcePool
  opt :cpu_limit, "CPU limit in Mhz", :type => :int
  opt :cpu_reservation, "CPU reservation in Mhz", :type => :int
  opt :cpu_shares, "CPU shares level or number", :default => 'normal'
  opt :cpu_expandable, "Whether CPU reservation can be expanded"
  opt :mem_limit, "Memory limit in MB", :type => :int
  opt :mem_reservation, "Memory reservation in MB", :type => :int
  opt :mem_shares, "Memory shares level or number", :default => 'normal'
  opt :mem_expandable, "Whether memory reservation can be expanded"
end

def shares_from_string str
  case str
  when 'normal', 'low', 'high'
    { :level => str, :shares => 0 }
  when /^\d+$/
    { :level => 'custom', :shares => str.to_i }
  else
    err "Invalid shares argument #{str.inspect}"
  end
end

def create name, parent, opts
  spec = {
    :cpuAllocation => {
      :limit => opts[:cpu_limit],
      :reservation => opts[:cpu_reservation],
      :expandableReservation => opts[:cpu_expandable],
      :shares => shares_from_string(opts[:cpu_shares]),
    },
    :memoryAllocation => {
      :limit => opts[:mem_limit],
      :reservation => opts[:mem_reservation],
      :expandableReservation => opts[:mem_expandable],
      :shares => shares_from_string(opts[:mem_shares]),
    },
  }
  parent.CreateResourcePool(:name => name, :spec => spec)
end


opts :update do
  summary "Update a resource pool"
  arg :pool, nil, :lookup => RbVmomi::VIM::ResourcePool
  opt :name, "New name for the resource pool", :type => :string
  opt :cpu_limit, "CPU limit in Mhz", :type => :int
  opt :cpu_reservation, "CPU reservation in Mhz", :type => :int
  opt :cpu_shares, "CPU shares level or number", :default => 'normal'
  opt :cpu_expandable, "Whether CPU reservation can be expanded"
  opt :mem_limit, "Memory limit in MB", :type => :int
  opt :mem_reservation, "Memory reservation in MB", :type => :int
  opt :mem_shares, "Memory shares level or number", :default => 'normal'
  opt :mem_expandable, "Whether memory reservation can be expanded"
end

def update pool, opts
  spec = {
    :cpuAllocation => {
      :limit => opts[:cpu_limit],
      :reservation => opts[:cpu_reservation],
      :expandableReservation => opts[:cpu_expandable],
      :shares => shares_from_string(opts[:cpu_shares]),
    },
    :memoryAllocation => {
      :limit => opts[:mem_limit],
      :reservation => opts[:mem_reservation],
      :expandableReservation => opts[:mem_expandable],
      :shares => shares_from_string(opts[:mem_shares]),
    },
  }
  pool.UpdateConfig(:name => opts[:name], :spec => spec)
end
