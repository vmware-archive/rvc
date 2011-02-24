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

  def ls
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
      :propSet => [
        { :type => 'ManagedEntity', :pathSet => %w(name) }
      ]
    )

    result = $vim.propertyCollector.RetrieveProperties(:specSet => [filterSpec])
    result.each do |r|
      if r.obj.is_a? VIM::Folder
        puts r['name'] + "/"
      else
        puts r['name']
      end
    end
  end
end

end
