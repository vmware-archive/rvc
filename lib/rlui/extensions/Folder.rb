class RbVmomi::VIM::Folder
  def traverse_one arc
    @soap.searchIndex.FindChild :entity => self, :name => arc
  end

  def ls_children
    RLUI::Util.collect_children self, :childEntity
  end

  def self.ls_properties
    %w(name)
  end

  def self.ls_text r
    "/"
  end

  def self.folder?
    true
  end
end
