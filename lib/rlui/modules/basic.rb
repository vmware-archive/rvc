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
  els = path.split '/'
  relative = !els.empty? && els[0].empty?
  $mode.cd els, relative
end

def mode name
  err "no such mode" unless MODES.member? name.to_sym
  $mode = MODES[name.to_sym]
end
