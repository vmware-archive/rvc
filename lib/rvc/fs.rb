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

class FS
  attr_reader :root, :cur, :marks

  MARK_PATTERN = /^~(?:([\d\w]*|~|@))$/
  REGEX_PATTERN = /^%/
  GLOB_PATTERN = /\*/

  def initialize root
    fail unless root.is_a? RVC::InventoryObject
    @root = root
    @cur = root
    @marks = {}
  end

  def display_path
    @cur.rvc_path.map { |arc,obj| arc } * '/'
  end

  def cd dst
    fail unless dst.is_a? RVC::InventoryObject
    @marks['~'] = [@cur]
    @cur = dst
  end

  def lookup path
    arcs, absolute, trailing_slash = Path.parse path
    base = absolute ? @root : @cur
    traverse(base, arcs)
  end

  # Starting from base, traverse each path element in arcs. Since the path
  # may contain wildcards, this function returns a list of matches.
  def traverse base, arcs
    objs = [base]
    arcs.each_with_index do |arc,i|
      objs.map! { |obj| traverse_one obj, arc, i==0 }
      objs.flatten!
    end
    objs
  end

  def traverse_one cur, arc, first
    case arc
    when '.'
      [cur]
    when '..'
      [cur.rvc_parent ? cur.rvc_parent : cur]
    when '...'
      # XXX shouldnt be nil
      [(cur.respond_to?(:parent) && cur.parent) ? cur.parent : (cur.rvc_parent || cur)]
    when MARK_PATTERN
      if first and objs = @marks[$1]
        objs
      else
        []
      end
    when REGEX_PATTERN
      regex = Regexp.new($')
      cur.rvc_children.select { |k,v| k =~ regex }.map { |k,v| v.rvc_link(cur, k); v }
    when GLOB_PATTERN
      regex = glob_to_regex arc
      cur.rvc_children.select { |k,v| k =~ regex }.map { |k,v| v.rvc_link(cur, k); v }
    else
      # XXX check for ambiguous child
      if first and arc =~ /^\d+$/ and objs = @marks[arc]
        objs
      else
        if child = cur.traverse_one(arc)
          child.rvc_link cur, arc
          [child]
        else
          []
        end
      end
    end
  end

  def delete_numeric_marks
    @marks.reject! { |k,v| k =~ /^\d+$/ }
  end

  # Utility methods

  def lookup_single path
    objs = lookup path
    Util.err "Not found: #{path.inspect}" if objs.empty?
    Util.err "More than one match for #{path.inspect}" if objs.size > 1
    objs.first
  end

  def lookup! path, types
    types = [types] unless types.is_a? Enumerable
    lookup(path).tap do |objs|
      objs.each do |obj|
        Util.err "Expected #{types*'/'} but got #{obj.class} at #{path.inspect}" unless types.any? { |type| obj.is_a? type }
      end
    end
  end

  def lookup_single! path, type
    objs = lookup!(path, type)
    Util.err "Not found: #{path.inspect}" if objs.empty?
    Util.err "More than one match for #{path.inspect}" if objs.size > 1
    objs.first
  end

private

  def glob_to_regex str
    Regexp.new "^#{Regexp.escape(str.gsub('*', "\0")).gsub("\0", ".*")}$"
  end
end

end
