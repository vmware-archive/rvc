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

require 'rvc/vim'

opts :mark do
  summary "Save an object for later use"
  arg :key, "Name for this mark"
  arg :obj, "Any objects", :required => false, :default => ['.'], :multi => true, :lookup => Object
end

rvc_alias :mark
rvc_alias :mark, :m

def mark key, objs
  err "invalid mark name" unless key =~ /^\w+$/
  shell.fs.marks[key] = objs
end


opts :edit do
  summary "Edit objects referenced by a mark"
  arg :key, "Name of mark"
end

rvc_alias :edit, :me

def edit key
  editor = ENV['VISUAL'] || ENV['EDITOR'] || 'vi'
  objs = shell.fs.marks[key] or err "no such mark #{key.inspect}"
  filename = File.join(Dir.tmpdir, "rvc.#{Time.now.to_i}.#{rand(65536)}")
  File.open(filename, 'w') { |io| objs.each { |obj| io.puts(obj.rvc_path_str) } }
  begin
    system("#{editor} #{filename}")
    new_paths = File.readlines(filename).map(&:chomp) rescue return
    new_objs = new_paths.map { |path| lookup(path) }.inject([], &:+)
    mark key, new_objs
  ensure
    File.unlink filename
  end
end


opts :list do
  summary "List marks"
end

def list
  shell.fs.marks.each { |k,v| puts k }
end
