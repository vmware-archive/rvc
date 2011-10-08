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

# opts :create_portgroup do
#   summary "Create a new portgroup on a vDS"
#   arg :name, "vDS", :lookup_parent => VIM::DistributedVirtualSwitch
#   #opt :pool, "Resource pool", :short => 'p', :type => :string, :lookup => VIM::ResourcePool
#   #opt :host, "Host", :short => 'h', :type => :string, :lookup => VIM::HostSystem
#   #opt :datastore, "Datastore", :short => 'd', :type => :string, :lookup => VIM::Datastore
#   #opt :disksize, "Size in KB of primary disk (or add a unit of <M|G|T>)", :short => 's', :type => :string, :default => "4000000"
#   #opt :memory, "Size in MB of memory", :short => 'm', :type => :int, :default => 128
#   #opt :cpucount, "Number of CPUs", :short => 'c', :type => :int, :default => 1
#   text <<-EOB

# Example:
#   vm.create -p ~foo/resourcePool/pools/prod -d ~data/bigdisk -s 10g ~vms/new

#   EOB
# end

# def 
