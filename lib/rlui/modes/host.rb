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

  def _ls_select_set
    [
      VIM.TraversalSpec(
        :name => 'tsFolderChildren',
        :type => 'Folder',
        :path => 'childEntity',
        :skip => false
      ),
      VIM.TraversalSpec(
        :name => 'tsComputeResourceHosts',
        :type => 'ComputeResource',
        :path => 'host',
        :skip => false
      ),
      VIM.TraversalSpec(
        :name => 'tsComputeResourceResourcePools',
        :type => 'ComputeResource',
        :path => 'resourcePool',
        :skip => false
      ),
      VIM.TraversalSpec(
        :name => 'tsResourcePoolChildren',
        :type => 'ResourcePool',
        :path => 'resourcePool',
        :skip => false
      ),
    ]
  end

  LS_PROPS = {
    :Folder => %w(name),
    :ComputeResource => %w(name summary.effectiveCpu summary.effectiveMemory),
    :ClusterComputeResource => %w(name summary.effectiveCpu summary.effectiveMemory),
    :HostSystem => %w(name summary.hardware.memorySize summary.hardware.cpuModel
                      summary.hardware.cpuMhz summary.hardware.numCpuPkgs
                      summary.hardware.numCpuCores summary.hardware.numCpuThreads),
    :ResourcePool => %w(name),
  }

  def ls
    clear_items
    _ls(LS_PROPS).each do |r|
      i = add_item r['name'], r.obj
      case r.obj
      when VIM::Folder
        puts "#{i} #{r['name']}/"
      when VIM::ClusterComputeResource
        puts "#{i} #{r['name']} (cluster): cpu #{r['summary.effectiveCpu']/1000} GHz, memory #{r['summary.effectiveMemory']/1000} GB"
      when VIM::ComputeResource
        puts "#{i} #{r['name']} (standalone): cpu #{r['summary.effectiveCpu']/1000} GHz, memory #{r['summary.effectiveMemory']/1000} GB"
      when VIM::HostSystem
        memorySize, cpuModel, cpuMhz, numCpuPkgs, numCpuCores =
          %w(memorySize cpuModel cpuMhz numCpuPkgs numCpuCores).map { |x| r["summary.hardware.#{x}"] }
        puts "#{i} #{r['name']} (host): cpu #{numCpuPkgs}*#{numCpuCores}*#{"%.2f" % (cpuMhz.to_f/1000)} GHz, memory #{"%.2f" % (memorySize/10**9)} GB"
      else
        puts "#{i} #{r['name']}"
      end
    end
  end
end

end

