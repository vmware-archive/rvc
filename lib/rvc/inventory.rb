module RVC

module InventoryObject
  module ClassMethods
    def ls_properties
      %w()
    end

    def folder?
      false
    end
  end

  def self.included m
    m.extend ClassMethods
  end

  def display_info
    puts "name: #{name}"
    puts "type: #{self.class.name}"
  end

  def ls_text r
    self.class.folder? ? '/' : ''
  end

  def traverse_one arc
    children[arc]
  end

  def children
    {}
  end

  def parent
    nil
  end
end

class FakeFolder
  include RVC::InventoryObject

  def initialize target, method
    @target = target
    @method = method
  end

  def children
    @target.send @method
  end

  def self.folder?
    true
  end

  def parent
    @target
  end

  def eql? x
    @target == x.instance_variable_get(:@target) &&
      @method == x.instance_variable_get(:@method)
  end

  def hash
    @target.hash ^ @method.hash
  end
end

class RootNode
  include RVC::InventoryObject

  def children
    Hash[$connections.map do |name,conn|
      [name, ConnectionNode.new(conn,self)]
    end]
  end

  def parent
    nil
  end

  def self.folder?
    true
  end
end

class ConnectionNode
  include RVC::InventoryObject

  def initialize connection, parent
    @connection = connection
    @parent = parent
  end

  def children
    @connection.rootFolder.children
  end

  def parent
    @parent
  end

  def self.folder?
    true
  end
end

end
