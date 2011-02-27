module RLUI

class Context
  attr_reader :items, :root, :cur

  def initialize root
    @root = root
    @cur = root
    @items = {}
    @next_item_index = 0
    @path = []
  end

  def display_path
    @path * '/'
  end

  def parse_path path
    els = path.split '/'
    absolute = els[0].nil? || els[0].empty?
    els.shift if absolute
    [els, absolute]
  end

  def lookup path
    case path
    when Integer
      @items[path] or fail("no such item")
    when String
      els, absolute = parse_path path
      base = absolute ? @root : cur
      traverse(base, els) or fail("not found")
    else fail
    end
  end

  def traverse base, els
    els.inject(base) do |cur,el|
      case el
      when '.'
        cur
      when '..'
        cur == @root ? cur : cur.parent
      else
        traverse_one(cur, el) or fail("no such arc #{el}")
      end
    end
  end

  def traverse_one cur, el
    case cur
    when VIM::ManagedEntity
      $vim.searchIndex.FindChild(:entity => cur, :name => el)
    else
      fail "not a container"
    end
  end

  def cd path
    els, absolute = parse_path path
    new_cur = absolute ? @root : @cur
    new_path = absolute ? [] : @path.dup
    els.each do |el|
      if el == '..'
        new_cur = new_cur.parent unless new_cur == @root
        new_path.pop
      else
        prev = new_cur
        new_cur = traverse_one(new_cur, el) or fail("no such arc #{el}")
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
