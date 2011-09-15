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
  if mod = RVC::MODULES[path]
    opts = mod.instance_variable_get(:@opts)
    opts.each do |method_name,method_opts|
      parser = RVC::OptionParser.new method_name, &method_opts
      help_summary parser, path, method_name
    end
    return
  elsif tgt = RVC::ALIASES[path]
    fail unless tgt =~ /^(.+)\.(.+)$/
    opts_block = RVC::MODULES[$1].opts_for($2.to_sym)
    RVC::OptionParser.new(tgt, &opts_block).educate
    return
  elsif path =~ /^(.+)\.(.+)$/ and
        mod = RVC::MODULES[$1] and
        opts_block = mod.opts_for($2.to_sym)
    RVC::OptionParser.new(path, &opts_block).educate
    return
  end

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
      help_summary parser, mod_name, method_name
    end
  end

  if not obj
    puts (<<-EOS)

To see detailed help for a command, use its --help option.
To show only commands relevant to a specific object, use "help /path/to/object".
    EOS
  end
end

def help_summary parser, mod_name, method_name
  aliases = ALIASES.select { |k,v| v == "#{mod_name}.#{method_name}" }.map(&:first)
  aliases_text = aliases.empty? ? '' : " (#{aliases*', '})"
  puts "#{mod_name}.#{method_name}#{aliases_text}: #{parser.summary?}" if parser.summary?
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
  arg :obj, "Directory to change to", :lookup => Object
end

rvc_alias :cd

def cd obj
  $shell.fs.cd(obj)
  $shell.session.set_mark '', [find_ancestor(RbVmomi::VIM::Datacenter)].compact
  $shell.session.set_mark '@', [find_ancestor(RbVmomi::VIM)].compact
  $shell.delete_numeric_marks
end

def find_ancestor klass
  $shell.fs.cur.rvc_path.map { |k,v| v }.reverse.find { |x| x.is_a? klass }
end


opts :ls do
  summary "List objects in a directory"
  arg :obj, "Directory to list", :required => false, :default => '.', :lookup => Object
end

rvc_alias :ls
rvc_alias :ls, :l

def ls obj
  children = obj.children
  name_map = children.invert
  children, fake_children = children.partition { |k,v| v.is_a? VIM::ManagedEntity }
  i = 0

  fake_children.each do |name,child|
    puts "#{i} #{name}#{child.ls_text(nil)}"
    child.rvc_link obj, name
    CMD.mark.mark i.to_s, [child]
    i += 1
  end

  return if children.empty?

  filterSpec = VIM.PropertyFilterSpec(:objectSet => [], :propSet => [])
  filteredTypes = Set.new

  children.each do |name,child|
    filterSpec.objectSet << { :obj => child }
    filteredTypes << child.class
  end

  filteredTypes.each do |x|
    filterSpec.propSet << {
      :type => x.wsdl_name,
      :pathSet => x.ls_properties+%w(name overallStatus),
    }
  end

  connection = single_connection(children.map { |k,v| v })
  results = connection.propertyCollector.RetrieveProperties(:specSet => [filterSpec])

  results.each do |r|
    name = name_map[r.obj]
    text = r.obj.ls_text(r) rescue " (error)"
    realname = r['name'] if name != r['name']
    colored_name = $terminal.color(name, *LS_COLORS[r['overallStatus']])
    puts "#{i} #{colored_name}#{realname && " [#{realname}]"}#{text}"
    r.obj.rvc_link obj, name
    CMD.mark.mark i.to_s, [r.obj]
    i += 1
  end
end

LS_COLORS = {
  'gray' => [],
  'red' => [:red],
  'green' => [],
  'yellow' => [:yellow],
}

opts :info do
  summary "Display information about an object"
  arg :path, nil, :lookup => Object
end  

rvc_alias :info
rvc_alias :info, :i

def info obj
  puts "path: #{obj.rvc_path_str}"
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


opts :reload_entity do
  summary "Synchronize management server state"
  arg :obj, nil, :lookup => VIM::ManagedEntity, :multi => true
end

rvc_alias :reload_entity

def reload_entity objs
  objs.each(&:Reload)
end


opts :show do
  summary "Basic information about the given objects"
  arg :obj, nil, :multi => true, :required => false, :lookup => Object
end

rvc_alias :show
rvc_alias :show, :w

def show objs
  objs.each do |obj|
    puts "#{obj.rvc_path_str}: #{obj.class}"
  end
end


opts :mv do
  summary "Move entities to another folder"
  text "The entities' names are unchanged."
  arg :objs, "Entities to move", :lookup => VIM::ManagedEntity, :multi => true
end

rvc_alias :mv

def mv objs
  err "Destination entity missing" unless objs.size > 1
  dst = objs.pop
  progress [dst.MoveIntoFolder_Task(:list => objs)]
end


opts :rename do
  summary "Rename an entity"
  arg :objs, "Entity to rename", :lookup => VIM::ManagedEntity
  arg :name, "New name"
end

rvc_alias :rename

def rename obj, name
  progress [obj.Rename_Task(:newName => name)]
end


opts :disconnect do
  summary "Disconnect from a server"
  arg :connection, nil, :type => :string, :lookup => RbVmomi::VIM
end

rvc_alias :disconnect

def disconnect connection
  k, = $shell.connections.find { |k,v| v == connection }
  $shell.connections.delete k
  $shell.session.set_connection k, nil
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


opts :events do
  summary "Show recent events"
  arg :obj, nil, :required => false, :default => '.', :lookup => Object
  opt :lines, "Output the last N events", :short => 'n', :type => :int, :default => 10
end

rvc_alias :events

def events obj, opts
  err "'events' not supported at this level" unless obj.respond_to?(:_connection)
  manager = obj._connection.serviceContent.eventManager
  @event_details ||= Hash[manager.collect("description.eventInfo").first.collect { |d| [d.key, d] }]

  spec = VIM::EventFilterSpec(:entity => VIM::EventFilterSpecByEntity(:entity => obj, :recursion => "all"))

  collector = manager.CreateCollectorForEvents(:filter => spec)
  collector.SetCollectorPageSize(:maxCount => opts[:lines])
  collector.latestPage.reverse.each do |event|
    time = event.createdTime.localtime.strftime("%m/%d/%Y %I:%M %p")
    category = @event_details[event.class.to_s].category
    puts "[#{time}] [#{category}] #{event.fullFormattedMessage.strip}"
  end
ensure
  collector.DestroyCollector if collector
end
