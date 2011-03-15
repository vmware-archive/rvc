class RbVmomi::VIM::ClusterComputeResource
  def self.ls_properties
    %w(name summary.effectiveCpu summary.effectiveMemory)
  end

  def ls_text r
    " (cluster): cpu #{r['summary.effectiveCpu']/1000} GHz, memory #{r['summary.effectiveMemory']/1000} GB"
  end

  # TODO add datastore, network
  def children
    hosts, resourcePool = collect *%w(host resourcePool)
    {
      'hosts' => RVC::FakeFolder.new(self, :rvc_host_children),
      'resourcePool' => resourcePool,
    }
  end

  def rvc_host_children
    RVC::Util.collect_children self, :host
  end
end
