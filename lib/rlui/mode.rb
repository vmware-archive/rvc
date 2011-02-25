module RLUI

class Mode
  attr_reader :display_path, :items, :root, :cur, :aliases

  def initialize root, initial_path
    @root = root
    @cur = root
    @items = {}
    @next_item_index = 0
    @aliases = {
      'type' => 'basic.type',
      'debug' => 'basic.debug',
      'rc' => 'basic.rc',
      'reload' => 'basic.reload',
      'cd' => 'basic.cd',
      'ls' => 'basic.ls',
    }
    @path = initial_path
  end

  def display_path
    @path * '/'
  end

  def traverse_one cur, el
    case cur
    when VIM::Folder
      cur.find el
    else
      fail "not a container"
    end
  end

  def cd els, relative
    new_cur = relative ? @cur : @root
    new_path = @path.dup
    els.each do |el|
      if el == '..'
        new_cur = new_cur.parent unless new_cur == @root
        new_path.pop
      else
        new_cur = traverse_one(new_cur, el) or fail("no such folder")
        new_path.push el
      end
    end
    @cur = new_cur
    @path = new_path
  end

  def _ls_select_set
    [
      VIM.TraversalSpec(
        :name => 'tsFolder',
        :type => 'Folder',
        :path => 'childEntity',
        :skip => false
      )
    ]
  end

  def _ls propHash
    propSet = propHash.map { |k,v| { :type => k, :pathSet => v } }
    filterSpec = VIM.PropertyFilterSpec(
      :objectSet => [
        {
          :obj => @cur,
          :skip => true,
          :selectSet => _ls_select_set
        }
      ],
      :propSet => propSet
    )

    $vim.propertyCollector.RetrieveProperties(:specSet => [filterSpec])
  end

  def clear_items
    @items.clear
    @next_item_index = 0
  end

  def add_item name, obj
    i = @next_item_index
    @next_item_index += 1
    @items[i] = obj
    @items[name] = obj
    i
  end

  def ls
    clear_items
    _ls(:ManagedEntity => %w(name)).each do |r|
      i = add_item r['name'], r.obj
      case r.obj
      when VIM::Folder
        puts "#{i} #{r['name']}/"
      else
        puts "#{i} #{r['name']}"
      end
    end
  end
end

end

require 'rlui/modes/vm'
require 'rlui/modes/datastore'
require 'rlui/modes/network'
require 'rlui/modes/host'
