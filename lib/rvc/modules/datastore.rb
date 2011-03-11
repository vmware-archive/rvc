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
