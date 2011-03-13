class RbVmomi::VIM::Folder
  def traverse_one arc
    @soap.searchIndex.FindChild :entity => self, :name => arc
  end

  def children
    RVC::Util.collect_children self, :childEntity
  end

  def self.folder?
    true
  end
end
