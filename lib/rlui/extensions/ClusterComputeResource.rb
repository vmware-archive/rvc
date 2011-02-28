class RbVmomi::VIM::ClusterComputeResource
  def self.ls_properties
    %w(name summary.effectiveCpu summary.effectiveMemory)
  end

  def self.ls_text r
    " (cluster): cpu #{r['summary.effectiveCpu']/1000} GHz, memory #{r['summary.effectiveMemory']/1000} GB"
  end
end
