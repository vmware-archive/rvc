class RbVmomi::VIM::Datacenter
  def children
    vmFolder, datastoreFolder, networkFolder, hostFolder =
      collect *%w(vmFolder datastoreFolder networkFolder hostFolder)
    {
      'vm' => vmFolder,
      'datastore' => datastoreFolder,
      'network' => networkFolder,
      'host' => hostFolder,
    }
  end
end
