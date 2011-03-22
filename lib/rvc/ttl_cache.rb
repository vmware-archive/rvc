# Copyright (c) 2011 VMware, Inc.  All Rights Reserved.

module RVC

class TTLCache
  Entry = Struct.new(:value, :time)

  def initialize ttl
    @ttl = ttl
    @cache = {}
  end

  def [] obj, sym, *args
    @cache.delete_if { |k,v| v.time + @ttl < Time.now }
    key = [obj,sym,*args]
    if e = @cache[key]
      e.value
    else
      value = obj.send(sym, *args)
      @cache[key] = Entry.new value, Time.now
      value
    end
  end
end

end
