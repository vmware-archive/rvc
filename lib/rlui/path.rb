module RLUI
module Path
  def self.parse path
    if path.empty?
      return [[], false, false]
    elsif path == '/'
      return [[], true, true]
    else
      els = path.split '/'
      trailing_slash = path[-1..-1] == '/'
      absolute = !els[0].nil? && els[0].empty?
      els.shift if absolute
      [els, absolute, trailing_slash]
    end
  end
end
end
