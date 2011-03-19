include RVC::Util

opts :type do
  summary "Display information about a VMODL type"
  arg :name, "VMODL type name"
end

def type name
  klass = RbVmomi::VIM.type(name) rescue err("invalid type #{name.inspect}")
  q = lambda { |x| x =~ /^xsd:/ ? $' : x }
  if klass < RbVmomi::VIM::DataObject
    puts "Data Object #{klass}"
    klass.full_props_desc.each do |desc|
      puts " #{desc['name']}: #{q[desc['wsdl_type']]}#{desc['is-array'] ? '[]' : ''}"
    end
  elsif klass < RbVmomi::VIM::ManagedObject
    puts "Managed Object #{klass}"
    puts
    puts "Properties:"
    klass.full_props_desc.each do |desc|
      puts " #{desc['name']}: #{q[desc['wsdl_type']]}#{desc['is-array'] ? '[]' : ''}"
    end
    puts
    puts "Methods:"
    klass.full_methods_desc.sort_by(&:first).each do |name,desc|
      params = desc['params']
      puts " #{name}(#{params.map { |x| "#{x['name']} : #{q[x['wsdl_type'] || 'void']}#{x['is-array'] ? '[]' : ''}" } * ', '}) : #{q[desc['result']['wsdl_type'] || 'void']}"
    end
  else
    err("cannot introspect type #{klass}")
  end
  nil
end

opts :help do
  summary "Display this text"
  arg :path, "Limit commands to those applicable to the given object", :required => false
end

HELP_ORDER = %w(basic vm)

def help path
  obj = lookup(path) if path

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
      aliases = ALIASES.select { |k,v| v == "#{mod_name}.#{method_name}" }.keys
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

def debug
  $connections.each do |name,conn|
    conn.debug = !conn.debug
  end
end

opts :quit do
  summary "Exit RVC"
end

def quit
  exit
end

opts :rc do
  summary "Reread ~/.rvcrc"
end

def rc
  RVC.reload_rc
end

opts :reload do
  summary "Reload RVC command modules"
end

def reload
  RVC.reload_modules
end

opts :cd do
  summary "Change directory"
  arg :path, "Directory to change to"
end

def cd path
  $context.cd(path) or err "Not found: #{path.inspect}"
  dc_loc = $context.loc.dup
  dc_loc.pop while dc_loc.obj and not dc_loc.obj.is_a? VIM::Datacenter
  dc_loc = nil if dc_loc.obj == nil
  $context.mark '', dc_loc
end

opts :ls do
  summary "List objects in a directory"
  arg :path, "Directory to list", :required => false, :default => '.'
end

def ls path
  loc = $context.lookup_loc(path) or err "Not found: #{path.inspect}"
  obj = loc.obj
  children = obj.children
  name_map = children.invert
  children, fake_children = children.partition { |k,v| v.is_a? VIM::ManagedEntity }
  i = 0

  fake_children.each do |name,obj|
    puts "#{i} #{name}#{obj.ls_text(nil)}"
    mark_loc = loc.dup.tap { |x| x.push name, obj }
    $context.mark i.to_s, mark_loc
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
    $context.mark i.to_s, mark_loc
    i += 1
  end
end

opts :info do
  summary "Display information about an object"
  arg :path, nil, :lookup => RVC::InventoryObject
end  

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

def destroy objs
  progress objs, :Destroy
end

opts :mark do
  summary "Save a path for later use"
  arg :key, "Name for this mark"
  arg :path, "Any object", :required => false, :default => '.'
end

def mark key, path
  err "invalid mark name" unless key =~ /^\w+$/
  obj = $context.lookup_loc(path) or err "Not found: #{path.inspect}" 
  $context.mark key, obj
end

opts :mv do
  summary "Move/rename an entity"
  arg :src, "Source path"
  arg :dst, "Destination path"
end

def mv src, dst
  src_dir = File.dirname(src)
  dst_dir = File.dirname(dst)
  err "cross-directory mv not yet supported" unless src_dir == dst_dir
  dst_name = File.basename(dst)
  obj = lookup(src)
  obj.Rename_Task(:newName => dst_name).wait_for_completion
end
