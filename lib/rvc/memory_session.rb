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
    fail "not an array" unless objs.is_a? Array
    @marks[key] = objs
  end

  def connections
    @connections.keys
  end

  def get_connection key
    @connections[key]
  end

  def set_connection key, conn
    @connections[key] = conn
  end
end

end
