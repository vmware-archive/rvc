# Copyright (c) 2011 VMware, Inc.  All Rights Reserved.
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

module RVC

class Location
  attr_reader :stack

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

class FS
  attr_reader :root, :loc, :marks

  MARK_REGEX = /^~(?:([\d\w]*|~|@))$/

  def initialize root
    @root = root
    @loc = Location.new root
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
    new_loc = lookup_loc(path) or return false
    mark '~', @loc
    @loc = new_loc
    true
  end

  def lookup_loc path
    els, absolute, trailing_slash = Path.parse path
    base_loc = absolute ? Location.new(@root) : @loc
    traverse(base_loc, els)
  end

  def traverse base_loc, els
    loc = base_loc.dup
    els.each_with_index do |el,i|
      case el
      when '.'
      when '..'
        loc.pop unless loc.obj == @root
      when '...'
        loc.push(el, loc.obj.parent) unless loc.obj == @root
      when MARK_REGEX
        return unless i == 0
        loc = @marks[$1] or return
        loc = loc.dup
      else
        # XXX check for ambiguous child
        if i == 0 and el =~ /^\d+$/ and @marks.member? el
          loc = @marks[el].dup
        else
          x = loc.obj.traverse_one(el) or return
          loc.push el, x
        end
      end
    end
    loc
  end

  def mark key, loc
    if loc == nil
      @marks.delete key
    else
      @marks[key] = loc
    end
  end
end

end
