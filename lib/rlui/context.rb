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
    trailing_slash = path[-1..-1] == '/'
    absolute = els[0].nil? || els[0].empty?
    els.shift if absolute
    [els, absolute, trailing_slash]
  end

  def lookup path
    case path
    when Integer
      @items[path] or fail("no such item")
    when String
      els, absolute, trailing_slash = parse_path path
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
        cur.traverse_one(el) or return
      end
    end
  end

  def cd path
    els, absolute, trailing_slash = parse_path path
    new_cur = absolute ? @root : @cur
    new_path = absolute ? [] : @path.dup
    els.each do |el|
      if el == '..'
        new_cur = new_cur.parent unless new_cur == @root
        new_path.pop
      else
        prev = new_cur
        new_cur = new_cur.traverse_one(el) or err("no such entity #{el}")
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
