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
  opt :num_ports, "Number of Ports", :short => 'n', :type => :int
  opt :type, "Portgroup Type (i.e. 'earlyBinding', 'ephemeral', 'lateBinding'",
      :short => 't', :type => :string, :default => 'earlyBinding'
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
      :short => 'v', :type => :string
end

def create dest, opts
  folder, name = *dest
  tasks [folder], :CreateDVS, :spec => { :configSpec => { :name => name },
                                         :productInfo => {
                                           :version => opts[:vds_version] } }
end
