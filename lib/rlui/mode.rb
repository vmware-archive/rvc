module RLUI

class Mode
  def initialize root
    @root = root
    @cur = root
  end

  # Array of string path elements
  def path
    @cur.pretty_path.split '/'
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
