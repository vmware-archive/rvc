module RLUI

class Location
  def initialize root
    @stack = [['', root]]
  end

  def initialize_copy src
    super
    @stack = @stack.dup
  end

  def push name, obj
    @stack << [name, obj]
  end

  def pop
    @stack.pop
  end

  def obj
    @stack.empty? ? nil : @stack[-1][1]
  end

  def path
    @stack.map { |name,obj| name }
  end
end

class Context
  attr_reader :root, :loc, :marks

  MARK_REGEX = /^~([\d\w]+)$/

  def initialize root
    @root = root
    @loc = Location.new root
    @prev_loc = @loc
    @marks = {}
  end

  def cur
    @loc.obj
  end

  def display_path
    @loc.path * '/'
  end

  def lookup path
    (lookup_loc(path) || return).obj
  end

  def cd path
    new_loc = lookup_loc(path) or return
    @prev_loc = @loc
    @loc = new_loc
  end

  def lookup_loc path
    case path
    when MARK_REGEX
      @marks[$1] or err("mark not set")
    when '~~'
      @prev_loc
    else
      els, absolute, trailing_slash = Path.parse path
      base_loc = absolute ? Location.new(@root) : @loc
      found_loc = traverse(base_loc, els) or err("not found")
    end
  end

  def traverse base_loc, els
    loc = base_loc.dup
    els.each do |el|
      case el
      when '.'
        loc.push el, cur
      when '..'
        loc.pop unless loc.obj == @root
      when '...'
        loc.push(el, loc.obj.parent) unless loc.obj == @root
      else
        x = loc.obj.traverse_one(el) or return
        loc.push el, x
      end
    end
    loc
  end

  def mark key, loc
    @marks[key] = loc
  end
end

end
