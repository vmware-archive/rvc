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

opts :type do
  summary "Display information about a VMODL type"
  arg :name, "VMODL type name"
end

rvc_alias :type

def type name
  klass = RbVmomi::VIM.type(name) rescue err("#{name.inspect} is not a VMODL type.")
  $shell.introspect_class klass
  nil
end


opts :help do
  summary "Display this text"
  arg :path, "Limit commands to those applicable to the given object", :required => false
end

rvc_alias :help

HELP_ORDER = %w(basic vm)

def help path
  obj = lookup_single(path) if path

  if obj
    puts "Relevant commands for #{obj.class}:"
  else
    puts "All commands:"
  end

  MODULES.sort_by do |mod_name,mod|
    HELP_ORDER.index(mod_name) || HELP_ORDER.size
  end.each do |mod_name,mod|
    opts = mod.instance_variable_get(:@opts)
    opts.each do |method_name,method_opts|
      parser = RVC::OptionParser.new method_name, &method_opts
      next unless obj.nil? or parser.applicable.any? { |x| obj.is_a? x }
      aliases = ALIASES.select { |k,v| v == "#{mod_name}.#{method_name}" }.map(&:first)
      aliases_text = aliases.empty? ? '' : " (#{aliases*', '})"
      puts "#{mod_name}.#{method_name}#{aliases_text}: #{parser.summary?}" if parser.summary?
    end
  end

  if not obj
    puts (<<-EOS)

To see detailed help for a command, use its --help option.
To show only commands relevant to a specific object, use "help /path/to/object".
    EOS
  end
end


opts :debug do
  summary "Toggle VMOMI logging to stderr"
end

rvc_alias :debug

def debug
  debug = $shell.debug = !$shell.debug
  $shell.connections.each do |name,conn|
    conn.debug = debug
  end
end


opts :quit do
  summary "Exit RVC"
end

rvc_alias :quit
rvc_alias :quit, :exit
rvc_alias :quit, :q

def quit
  exit
end


opts :reload do
  summary "Reload RVC command modules"
end

rvc_alias :reload

def reload
  RVC.reload_modules
end


opts :cd do
  summary "Change directory"
  arg :path, "Directory to change to"
end

rvc_alias :cd

def cd path
  # XXX check for multiple matches
  new_loc = $shell.fs.lookup_loc(path).first or err "Not found: #{path.inspect}"
  $shell.fs.cd(new_loc)
  $shell.fs.mark '', find_ancestor_loc(RbVmomi::VIM::Datacenter)
  $shell.fs.mark '@', find_ancestor_loc(RbVmomi::VIM)
  $shell.fs.marks.delete_if { |k,v| k =~ /^\d+$/ }
end

def find_ancestor_loc klass
  dc_loc = $shell.fs.loc.dup
  dc_loc.pop while dc_loc.obj and not dc_loc.obj.is_a? klass
  dc_loc.obj ? dc_loc : nil
end


opts :ls do
  summary "List objects in a directory"
  arg :path, "Directory to list", :required => false, :default => '.'
end

rvc_alias :ls
rvc_alias :ls, :l

def ls path
  # XXX check for multiple matches
  loc = $shell.fs.lookup_loc(path).first or err "Not found: #{path.inspect}"
  obj = loc.obj
  children = obj.children
  name_map = children.invert
  children, fake_children = children.partition { |k,v| v.is_a? VIM::ManagedEntity }
  i = 0

  fake_children.each do |name,obj|
    puts "#{i} #{name}#{obj.ls_text(nil)}"
    mark_loc = loc.dup.tap { |x| x.push name, obj }
    $shell.fs.mark i.to_s, mark_loc
    i += 1
  end

  return if children.empty?

  filterSpec = VIM.PropertyFilterSpec(:objectSet => [], :propSet => [])
  filteredTypes = Set.new

  children.each do |name,obj|
    filterSpec.objectSet << { :obj => obj }
    filteredTypes << obj.class
  end

  filteredTypes.each do |x|
    filterSpec.propSet << {
      :type => x.wsdl_name,
      :pathSet => x.ls_properties+%w(name),
    }
  end

  connection = single_connection(children.map { |k,v| v })
  results = connection.propertyCollector.RetrieveProperties(:specSet => [filterSpec])

  results.each do |r|
    name = name_map[r.obj]
    text = r.obj.ls_text r
    realname = r['name'] if name != r['name']
    puts "#{i} #{name}#{realname && " [#{realname}]"}#{text}"
    mark_loc = loc.dup.tap { |x| x.push name, r.obj }
    $shell.fs.mark i.to_s, mark_loc
    i += 1
  end
end


opts :info do
  summary "Display information about an object"
  arg :path, nil, :lookup => Object
end  

rvc_alias :info
rvc_alias :info, :i

def info obj
  if obj.respond_to? :display_info
    obj.display_info
  else
    puts "class: #{obj.class.name}"
  end
end


opts :destroy do
  summary "Destroy managed entities"
  arg :obj, nil, :lookup => VIM::ManagedEntity, :multi => true
end

rvc_alias :destroy

def destroy objs
  tasks objs, :Destroy
end


opts :mark do
  summary "Save a path for later use"
  arg :key, "Name for this mark"
  arg :path, "Any object", :required => false, :default => '.'
end

rvc_alias :mark
rvc_alias :mark, :m

def mark key, path
  err "invalid mark name" unless key =~ /^\w+$/
  # XXX aggregate marks
  obj = $shell.fs.lookup_loc(path).first or err "Not found: #{path.inspect}" 
  $shell.fs.mark key, obj
end


opts :mv do
  summary "Move/rename an entity"
  arg :src, "Source path"
  arg :dst, "Destination path"
end

rvc_alias :mv

def mv src, dst
  src_dir = File.dirname(src)
  dst_dir = File.dirname(dst)
  err "cross-directory mv not yet supported" unless src_dir == dst_dir
  dst_name = File.basename(dst)
  obj = lookup(src)
  obj.Rename_Task(:newName => dst_name).wait_for_completion
end


opts :disconnect do
  summary "Disconnect from a server"
  arg :connection, nil, :type => :string, :lookup => RbVmomi::VIM
end

rvc_alias :disconnect

def disconnect connection
  $shell.connections.delete_if { |k,v| v == connection }
end


opts :mkdir do
  summary "Create a folder"
  arg :path, "Folder to create", :type => :string
end

rvc_alias :mkdir

# TODO dispatch to datastore.mkdir if path is in a datastore
def mkdir path
  parent = lookup_single! File.dirname(path), RbVmomi::VIM::Folder
  parent.CreateFolder(:name => File.basename(path))
end
