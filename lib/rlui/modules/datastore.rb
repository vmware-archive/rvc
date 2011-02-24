include RLUI::Util

def list
  tree = $dc.datastoreFolder.inventory(Datastore: %w(name summary.type summary.accessible summary.url))
  display_inventory tree, $dc.datastoreFolder do |obj,props,indent|
    puts "#{"  "*indent}#{props['name']}: #{props['summary.type']} #{props['summary.accessible'] ? props['summary.url'] : '<inaccessible>'}"
  end
end

