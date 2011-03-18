opts :download do
  summary "Download a file from a datastore"
  arg 'datastore-path', "Filename on the datastore"
  arg 'local-path', "Filename on the local machine"
end

def download datastore_path, local_path
  file = lookup(datastore_path)
  err "not a datastore file" unless file.is_a? RbVmomi::VIM::Datastore::FakeDatastoreFile
  file.datastore.download file.path, local_path
end

opts :upload do
  summary "Upload a file to a datastore"
  arg 'local-path', "Filename on the local machine"
  arg 'datastore-path', "Filename on the datastore"
end

def upload local_path, datastore_path
  datastore_dir_path = File.dirname datastore_path
  dir = lookup(datastore_dir_path)
  err "datastore directory does not exist" unless dir.is_a? RbVmomi::VIM::Datastore::FakeDatastoreFolder
  err "local file does not exist" unless File.exists? local_path
  real_datastore_path = "#{dir.path}/#{File.basename(datastore_path)}"
  dir.datastore.upload real_datastore_path, local_path
end

opts :mkdir do
  summary "Create a directory on a datastore"
  arg 'path', "Directory to create on the datastore"
end

def mkdir datastore_path
  datastore_dir_path = File.dirname datastore_path
  dir = lookup(datastore_dir_path)
  err "datastore directory does not exist" unless dir.is_a? RbVmomi::VIM::Datastore::FakeDatastoreFolder
  ds = dir.datastore
  dc = ds.path.find { |o,x| o.is_a? RbVmomi::VIM::Datacenter }[0]
  name = "#{dir.datastore_path}/#{File.basename(datastore_path)}"
  $vim.serviceContent.fileManager.MakeDirectory :name => name,
                                                :datacenter => dc,
                                                :createParentDirectories => false
end
