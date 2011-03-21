class RbVmomi::VIM::ManagedEntity
  include RVC::InventoryObject

  def display_info
    puts "name: #{name}"
    puts "type: #{self.class.name}"
  end
end
