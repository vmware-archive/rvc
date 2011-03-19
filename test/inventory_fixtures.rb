class FixtureNode
  include RVC::InventoryObject
  attr_accessor :parent
  attr_reader :children

  def initialize children={}
    @children = children
    @children.each { |k,v| v.parent = self }
  end
end
