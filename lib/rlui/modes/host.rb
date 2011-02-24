module RLUI

class HostMode < Mode
  def initialize *args
    super
    aliases.merge!(
      'info' => 'computer.info',
      'i' => 'computer.info',
    )
  end

  LS_PROPS = {
    :Folder => %w(name),
    :ComputeResource => %w(name summary.effectiveCpu summary.effectiveMemory),
    :ClusterComputeResource => %w(name summary.effectiveCpu summary.effectiveMemory),
  }

  def ls
    clear_items
    _ls(LS_PROPS).each do |r|
      i = add_item r['name'], r.obj
      case r.obj
      when VIM::Folder
        puts "#{i} #{r['name']}/"
      when VIM::ClusterComputeResource
        puts "#{i} #{r['name']} (cluster): cpu #{r['summary.effectiveCpu']/1000} ghz, memory #{r['summary.effectiveMemory']/1000} gb"
      when VIM::ComputeResource
        puts "#{i} #{r['name']}: cpu #{r['summary.effectiveCpu']/1000} ghz, memory #{r['summary.effectiveMemory']/1000} gb"
      else
        puts "#{i} #{r['name']}"
      end
    end
  end
end

end

