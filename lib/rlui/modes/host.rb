module RLUI

class HostMode < Mode
  def initialize *args
    super
    aliases.merge!(
      'info' => 'computer.info',
      'i' => 'computer.info',
    )
  end

  def traverse_one cur, el
    case cur
    when VIM::ComputeResource, VIM::ResourcePool
      $vim.searchIndex.FindChild(:entity => cur, :name => el)
    else
      super
    end
  end
end

end

