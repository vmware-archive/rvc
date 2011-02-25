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
end

end

require 'rlui/modes/vm'
require 'rlui/modes/datastore'
require 'rlui/modes/network'
require 'rlui/modes/host'
