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
    :ResourcePool => %w(name config.cpuAllocation config.memoryAllocation),
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
      when VIM::ResourcePool
        cpuAlloc, memAlloc = r['config.cpuAllocation'], r['config.memoryAllocation']

        cpu_shares_text = cpuAlloc.shares.level == 'custom' ? cpuAlloc.shares.shares.to_s : cpuAlloc.shares.level
        mem_shares_text = memAlloc.shares.level == 'custom' ? memAlloc.shares.shares.to_s : memAlloc.shares.level

        puts "#{i} #{r['name']} (resource pool): cpu %0.2f/%0.2f/%s, mem %0.2f/%0.2f/%s" % [
          cpuAlloc.reservation/1000.0, cpuAlloc.limit/1000.0, cpu_shares_text,
          memAlloc.reservation/1000.0, memAlloc.limit/1000.0, mem_shares_text,
        ]
      else
        puts "#{i} #{r['name']}"
      end
    end
  end
end

end

