module RLUI

class Context
  attr_reader :root, :cur, :stack

  def initialize root
    @root = root
    @cur = root
    @path = []
    @stack = []
  end

  def display_path
    @path * '/'
  end

  def lookup path
    case path
    when String
      els, absolute, trailing_slash = Path.parse path
      base = absolute ? @root : cur
      stack = absolute ? [] : @stack
      traverse(base, stack, els) or fail("not found")
    else fail
    end
  end

  def traverse base, stack, els
    stack = stack.dup
    els.inject(base) do |cur,el|
      case el
      when '.'
        cur
      when '..'
        stack.pop
        stack[-1] || @root
      when '...'
        cur == @root ? cur : cur.parent
      else
        x = cur.traverse_one(el) or return
        stack << x
        x
      end
    end
  end

  def cd path
    els, absolute, trailing_slash = Path.parse path
    new_cur = absolute ? @root : @cur
    new_path = absolute ? [] : @path.dup
    new_stack = absolute ? [] : @stack.dup
    els.each do |el|
      if el == '..'
        new_path.pop
        new_stack.pop
        new_cur = new_stack[-1] || @root
      elsif el == '...'
        new_cur = new_cur.parent unless new_cur == @root
        new_path.push el
        new_stack.push new_cur
      else
        new_cur = new_cur.traverse_one(el) or err("no such entity #{el}")
        new_path.push el
        new_stack.push new_cur
      end
    end
    @cur = new_cur
    @path = new_path
    @stack = new_stack
  end
end

end
