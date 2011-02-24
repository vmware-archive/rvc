module RLUI

class NetworkMode < Mode
  def initialize *args
    super
    aliases.merge!(
      'info' => 'network.info',
      'i' => 'network.info',
    )
  end

  LS_PROPS = {
    :Folder => %w(name),
    :Network => %w(name),
    :DistributedVirtualPortgroup => %w(name config.distributedVirtualSwitch),
    :DistributedVirtualSwitch => %w(name summary.description),
  }

  def ls
    clear_items
    _ls(LS_PROPS).each do |r|
      i = add_item r['name'], r.obj
      case r.obj
      when VIM::Folder
        puts "#{i} #{r['name']}/"
      when VIM::DistributedVirtualPortgroup
        # XXX optimize
        puts "#{i} #{r['name']} (dvpg) <#{r['config.distributedVirtualSwitch'].name}"
      when VIM::DistributedVirtualSwitch
        puts "#{i} #{r['name']} (dvs)"
      when VIM::Network
        puts "#{i} #{r['name']}"
      else
        puts "#{i} #{r['name']}"
      end
    end
  end
end

end

