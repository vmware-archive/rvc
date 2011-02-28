class RbVmomi::VIM::Datacenter
  def child_types
    {
      'vm' => RbVmomi::VIM::Folder,
      'datastore' => RbVmomi::VIM::Folder,
      'network' => RbVmomi::VIM::Folder,
      'host' => RbVmomi::VIM::Folder
    }
  end

  def traverse_one arc
    case arc
    when 'vm' then vmFolder
    when 'datastore' then datastoreFolder
    when 'network' then networkFolder
    when 'host' then hostFolder
    end
  end

  def ls_children
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
