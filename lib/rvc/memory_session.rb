module RVC

class MemorySession
  def initialize
    @marks = {}
    @connections = {}
  end

  def marks
    @marks.keys
  end

  def get_mark key
    @marks[key]
  end

  def set_mark key, objs
    if objs == nil
      @marks.delete key
    else
      fail "not an array" unless objs.is_a? Array
      @marks[key] = objs
    end
  end
end

end
