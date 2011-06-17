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
