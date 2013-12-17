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

require 'rvc/vim'
VIM::VirtualMachine

opts :create do
  summary "Snapshot a VM"
  arg :vm, nil, :lookup => VIM::VirtualMachine
  arg :name, "Name of new snapshot"
  opt :description, "Description", :short => 'd', :default => ""
  opt :quiesce, "Quiesce", :short => 'q', :default => false
  opt :memory, "Memory", :short => 'm', :default => true
end

def create vm, name, opts
  tasks [vm], :CreateSnapshot, :description => opts[:description], :memory => opts[:memory], :name => name, :quiesce => opts[:quiesce]
end

rvc_alias :create, :snapshot


opts :revert do
  summary "Revert a VM to a snapshot. Defaults to the current snapshot."
  arg :arg, nil, :lookup => [VIM::VirtualMachine, RVC::SnapshotFolder]
end

def revert arg
  if arg.is_a? VIM::VirtualMachine
    tasks [arg], :RevertToCurrentSnapshot
  else
    tasks [arg.find_tree.snapshot], :RevertToSnapshot
  end
end


opts :rename do
  summary "Rename a snapshot"
  arg :snapshot, nil, :lookup => RVC::SnapshotFolder
  arg :name, "New name", :type => :string
end

def rename snapshot, name
  snapshot.find_tree.snapshot.RenameSnapshot :name => name
end


opts :describe do
  summary "Change the description of a snapshot"
  arg :snapshot, nil, :lookup => RVC::SnapshotFolder
  arg :description, "New description", :type => :string
end

def describe snapshot, description
  snapshot.find_tree.snapshot.RenameSnapshot :description => description
end


opts :remove do
  summary "Remove snapshots"
  arg :snapshots, nil, :multi => true, :lookup => RVC::SnapshotFolder
  opt :remove_children, "Whether to remove the snapshot's children too"
  opt :no_consolidate, "Don't consolidate", :type => :boolean
end

def remove snapshots, opts
  # Sort by path and use reverse_each to remove child snapshots first
  snapshots.sort_by! {|s| s.rvc_path_str }

  snapshots.reverse_each do |snapshot|
    tasks(
      [snapshot.find_tree.snapshot], 
      :RemoveSnapshot, 
      :removeChildren => opts[:remove_children],
      :consolidate => !opts[:no_consolidate]
    )
  end
end
