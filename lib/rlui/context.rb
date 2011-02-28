module RLUI

class Context
  attr_reader :root, :cur

  def initialize root
    @root = root
    @cur = root
    @path = []
  end

  def display_path
    @path * '/'
  end

  def lookup path
    case path
    when String
      els, absolute, trailing_slash = Path.parse path
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
    els, absolute, trailing_slash = Path.parse path
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
end

end
