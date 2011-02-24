include RLUI::Util

def list
  props = %w(name summary.effectiveCpu summary.effectiveMemory)
  tree = $dc.hostFolder.inventory(:ComputeResource => props, :ClusterComputeResource => props)
  display_inventory tree, $dc.hostFolder do |obj,props,indent|
    case obj
    when VIM::ClusterComputeResource
      puts "#{"  "*indent}cluster #{props['name']}: cpu #{props['summary.effectiveCpu']/1000} ghz, memory #{props['summary.effectiveMemory']/1000} gb"
      obj.host.each do |host|
        puts "#{"  "*(indent+1)}host #{host.name}"
      end
    when VIM::ComputeResource
      puts "#{"  "*indent}host #{props['name']}: cpu #{props['summary.effectiveCpu']/1000} ghz, memory #{props['summary.effectiveMemory']/1000} gb"
    end
  end
end
