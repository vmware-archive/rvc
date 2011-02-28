class RbVmomi::VIM::ComputeResource
  # TODO expand, optimize
  def display_info
    puts "name: #{name}"
    puts "hosts:"
    host.each do |h|
      puts " #{h.name}"
    end
  end
end
