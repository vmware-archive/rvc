module RLUI

class FakeFolder
  def initialize target, method
    @target = target
    @method = method
  end

  def ls_text
    "/"
  end

  def ls_children
    @target.send @method
  end

  def child_types
    Hash[ls_children.map { |k,v| [k, v.class] }]
  end

  def traverse_one arc
    ls_children[arc]
  end

  def self.folder?
    true
  end
end

end
