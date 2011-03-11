opts :download do
  summary "Download a file from a datastore"
  usage "datastore-path local-path"
end

def download args
  datastore_path = args[0] or err "datastore path required"
  local_path = args[1] or err "local path required"
  file = lookup(datastore_path)
  err "not a datastore file" unless file.is_a? RVC::FakeDatastoreFile
  file.datastore.download file.path, local_path
end

opts :upload do
  summary "Upload a file to a datastore"
  usage "local-path datastore-path"
end

def upload args
  local_path = args[0] or err "local path required"
  datastore_path = args[1] or err "datastore path required"
  datastore_dir_path = File.dirname datastore_path
  dir = lookup(datastore_dir_path)
  err "datastore directory does not exist" unless dir.is_a? RVC::FakeDatastoreFolder
  err "local file does not exist" unless File.exists? local_path
  real_datastore_path = "#{dir.path}/#{File.basename(datastore_path)}"
  dir.datastore.upload real_datastore_path, local_path
end
