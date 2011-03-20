class FixtureNode
  include RVC::InventoryObject
  attr_accessor :parent
  attr_reader :children

  def initialize name, children={}
    @name = name
    @children = children
    @children.each { |k,v| v.parent = self }
  end

  def pretty_print pp
    pp.text "Node<#{@name}>"
  end
end
