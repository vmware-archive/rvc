module RLUI

class Mode
  attr_reader :display_path

  def initialize root
    @root = root
    @cur = root
  end

  def display_path
    @cached_display_path ||= @cur.pretty_path
  end

  def cd els, relative
    new_cur = @root unless relative
    els.each do |el|
      if el == '..'
        new_cur = new_cur.parent unless new_cur == @root
      else
        new_cur = new_cur.find(el, VIM::Folder) or fail("no such folder")
      end
    end
    @cached_display_path = nil unless @cur == new_cur
    @cur = new_cur
  end

  def _ls propHash
    propSet = propHash.map { |k,v| { :type => k, :pathSet => v } }
    filterSpec = VIM.PropertyFilterSpec(
      :objectSet => [
        :obj => @cur,
        :skip => true,
        :selectSet => [
          VIM.TraversalSpec(
            :name => 'tsFolder',
            :type => 'Folder',
            :path => 'childEntity',
            :skip => false
          )
        ]
      ],
      :propSet => propSet
    )

    $vim.propertyCollector.RetrieveProperties(:specSet => [filterSpec])
  end

  def ls
    _ls(:ManagedEntity => %w(name)).each do |r|
      case r.obj
      when VIM::Folder
        puts r['name'] + "/"
      else
        puts r['name']
      end
    end
  end
end

class VmMode < Mode
  def ls
    _ls(:Folder => %w(name), :VirtualMachine => %w(name runtime.powerState)).each do |r|
      case r.obj
      when VIM::Folder
        puts r['name'] + "/"
      when VIM::VirtualMachine
        puts "#{r['name']} #{r['runtime.powerState']}"
      else
        puts r['name']
      end
    end
  end
end

end
