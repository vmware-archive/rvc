class RbVmomi::VIM::ManagedEntity
  def display_info
    puts "name: #{name}"
    puts "type: #{self.class.wsdl_name}"
  end

  def child_types
    ls_children.map { |k,v| [k, v.class] }
  end

  def traverse_one arc
    ls_children[arc]
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

  def self.folder?
    false
  end
end
