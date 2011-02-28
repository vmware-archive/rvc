class RbVmomi::VIM::ManagedEntity
  def display_info
    puts "name: #{name}"
    puts "type: #{self.class.wsdl_name}"
  end

  def child_types
    {}
  end

  def traverse_one arc
    nil
  end

  def ls_children
    {}
  end

  def self.ls_properties
    %w(name)
  end

  def self.ls_text r
    ""
  end
end
