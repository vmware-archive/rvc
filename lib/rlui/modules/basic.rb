include RLUI::Util

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

def help
  puts(<<-EOS)
list - List all VMs. <id> is the first column.
on/off/reset/suspend id - VM power operations
register datastore path - Register a VM already in a datastore
unregister id - Unregister a VM from hostd
findvm [datastore] - Display a menu of VMX files to register
destroy id - Unregister VM and delete its files (DESTRUCTIVE)
kill id - Power off and destroy a VM (DESTRUCTIVE)
info id - Information about a VM
view id - Open a VMRC to this VM
ip id - Wait for the VM to get an IP, then display it
ssh id - SSH to this VM
rlui id - Run rlui against this VM
gdb id - Run debug-esx against this VM
ddt id - Run ddt-esx against this VM
ping id - Ping the VM
layout id - VM files information
devices id - List devices
computers - List compute resources in this datacenter
datastores - List datastores in this datacenter
networks - List networks in this datacenter
answer id choice - Answer a VM question
connect id label - Connect a virtual device
disconnect id label - Disconnect a virtual device
extraConfig [regex] - Display extraConfig options
setExtraConfig id key=value - Set extraConfig options
type name - Show the definition of a VMODL type
soap - Toggle display of SOAP messages
rc - Reload ~/.rluirc
  EOS
end

def debug
  $vim.debug = !$vim.debug
end

def quit
  exit
end

def rc
  RLUI.reload_rc
end

def reload
  RLUI.reload_modules
end

def cd path="/"
  $context.cd path
end

def ls path='.'
  obj = lookup(path)
  children = obj.ls_children
  name_map = children.invert
  children, fake_children = children.partition { |k,v| v.is_a? VIM::ManagedEntity }

  fake_children.each do |name,obj|
    puts "#{name}#{obj.ls_text}"
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
      :pathSet => x.ls_properties,
    }
  end

  results = $vim.propertyCollector.RetrieveProperties(:specSet => [filterSpec])

  results.each do |r|
    name = name_map[r.obj]
    text = r.obj.class.ls_text r
    realname = r['name'] if name != r['name']
    puts "#{name}#{realname && " [#{realname}]"}#{text}"
  end
end

def info path
  obj = lookup(path)
  expect obj, VIM::ManagedEntity
  obj.display_info
end

def destroy *paths
  progress paths, :Destroy
end
