class RbVmomi::VIM::ResourcePool
  def self.ls_properties
    %w(name config.cpuAllocation config.memoryAllocation)
  end

  def self.ls_text r
    cpuAlloc, memAlloc = r['config.cpuAllocation'], r['config.memoryAllocation']

    cpu_shares_text = cpuAlloc.shares.level == 'custom' ? cpuAlloc.shares.shares.to_s : cpuAlloc.shares.level
    mem_shares_text = memAlloc.shares.level == 'custom' ? memAlloc.shares.shares.to_s : memAlloc.shares.level

    ": cpu %0.2f/%0.2f/%s, mem %0.2f/%0.2f/%s" % [
      cpuAlloc.reservation/1000.0, cpuAlloc.limit/1000.0, cpu_shares_text,
      memAlloc.reservation/1000.0, memAlloc.limit/1000.0, mem_shares_text,
    ]
  end
end
