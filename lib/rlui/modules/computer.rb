include RLUI::Util

# XXX expand, optimize
def info id
  c = item(id, VIM::ComputeResource)
  case c
  when VIM::ClusterComputeResource
    puts "name: #{c.name}"
    puts "hosts:"
    c.host.each do |host|
      puts " #{host.name}"
    end
  when VIM::ComputeResource
    puts "name: #{c.name}"
  end
end
