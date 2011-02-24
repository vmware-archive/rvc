include RLUI::Util

def list
  tree = $dc.networkFolder.inventory(Network: %w(name host vm))
  display_inventory tree, $dc.networkFolder do |obj,props,indent|
    num_hosts = props['host'].size
    num_vms = props['vm'].size
    puts "#{"  "*indent}#{props['name']}: #{num_hosts} hosts, #{num_vms} vms"
  end
end

