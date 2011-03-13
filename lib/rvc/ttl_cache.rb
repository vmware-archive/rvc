module RVC

class TTLCache
  Entry = Struct.new(:value, :time)

  def initialize ttl
    @ttl = ttl
    @cache = {}
  end

  def [] obj, sym, *args
    key = [obj,sym,*args]
    if e = @cache[key] and e.time > Time.now - @ttl
      e.value
    else
      value = obj.send(sym, *args)
      @cache[key] = Entry.new value, Time.now
      value
    end
  end
end

end
