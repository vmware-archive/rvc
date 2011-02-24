include RLUI::Util

def list
  $items.clear
  tree = $vmFolder.inventory :VirtualMachine => %w(name runtime.powerState)
  display_inventory tree, $vmFolder do |obj,props,indent|
    i = _list_vm obj, props['name']
    puts "#{"  "*indent}#{i} #{props['name']} #{props['runtime.powerState']}"
  end
end

def _list_vm vm, name=vm.name
  i = $items.keys.select { |x| x.is_a? Integer }.max
  i = i ? i+1 : 0
  $items[i] = vm
  $items[name] = vm
  i
end

def on *ids
  vmtask ids, :PowerOnVM
end

def off *ids
  vmtask ids, :PowerOffVM
end

def reset *ids
  vmtask ids, :ResetVM
end

def suspend *ids
  vmtask ids, :SuspendVM
end

def register datastore, path
  path = "#{path}/#{path}.vmx" unless path =~ /\.vmx$/
  ds_path = "[#{datastore}] #{path}"

  resource = $dc.hostFolder.childEntity.first
  rp = resource.resourcePool
  puts "using compute resource #{resource.name}"
  vm = $vmFolder.RegisterVM_Task(:path => ds_path,
                                 :asTemplate => false,
                                 :pool => rp).wait_for_completion
  _list_vm vm
end

def unregister id
  vm(id).UnregisterVM
end

def destroy *ids
  vmtask ids, :Destroy
end

def kill *ids
  on_ids = ids.select { |x| vm(x).summary.runtime.powerState == 'poweredOn' }
  off *on_ids unless on_ids.empty?
  destroy *ids unless ids.empty?
end

def info id
  config, runtime, guest = vm(id).collect :config, :runtime, :guest

  puts "name: #{config.name}"
  puts "note: #{config.annotation}" if config.annotation and !config.annotation.empty?
  puts "host: #{runtime.host.path[1..-1].map { |x| x[1] } * '/'}" if runtime.host
  puts "tools: #{guest.toolsRunningStatus}"
  puts "hostname: #{guest.hostName} (#{guest.ipAddress})" if guest.hostName and guest.ipAddress
  puts "VC UUID: #{config.instanceUuid}" if config.instanceUuid and !config.instanceUuid.empty?
  puts "power: #{runtime.powerState}"
  if runtime.question
    puts "question: #{runtime.question.text.lines.to_a.join("> ")}"
    puts "choices: #{runtime.question.choice.choiceInfo.map(&:label) * ', '}"
    if i = runtime.question.choice.defaultIndex
      puts "default: #{runtime.question.choice.choiceInfo[i].label}"
    end
  end
  puts "cpus: #{config.hardware.numCPU}"
  puts "memory: #{config.hardware.memoryMB} MB"

  puts "nics:"
  config.hardware.device.grep VIM::VirtualEthernetCard do |dev|
    backing_info = case dev.backing
    when VIM::VirtualEthernetCardNetworkBackingInfo
      dev.backing.deviceName.inspect
    when VIM::VirtualEthernetCardDistributedVirtualPortBackingInfo
      dev.backing.port.portgroupKey.inspect
    else
      dev.backing.class.name
    end
    guest_net = guest.net.find { |x| x.macAddress == dev.macAddress }
    puts " #{dev.deviceInfo.label}: #{backing_info} #{dev.connectable.connected ? :connected : :disconnected} #{dev.macAddress} #{guest_net ? (guest_net.ipAddress * ' ') : ''}"
  end
end

def answer id, str
  q = vm(id).runtime.question or err("no question to answer")
  choice = q.choice.choiceInfo.find { |x| x.label == str }
  err("invalid answer") unless choice
  vm(id).AnswerVM :questionId => q.id, :answerChoice => choice.key
end

def layout id
  vm(id).layoutEx.file.each do |f|
    puts "#{f.type}: #{f.name}"
  end
end

def devices id
  devs = vm(id).config.hardware.device
  devs.each do |dev|
    tags = []
    tags << (dev.connectable.connected ? :connected : :disconnected) if dev.props.member? :connectable
    puts "#{dev.deviceInfo.label}: #{dev.deviceInfo.summary}; #{tags * ' '}"
  end
end

def connect id, label
  change_device_connectivity id, label, true
end

def disconnect id, label
  change_device_connectivity id, label, false
end

def find datastore_name=nil
  if not datastore_name
    datastore_names = $dc.datastore.map(&:name)
    if datastore_names.empty?
      puts "no datastores found"
      return
    end
    puts "Select a datastore:"
    datastore_name = menu(datastore_names) or return
  end

  paths = find_vmx_files(datastore_name)
  if paths.empty?
    puts "no VMX files found"
    return
  end

  puts "Select a VMX file"
  path = menu(paths) or return

  resource = $dc.hostFolder.childEntity.first
  rp = resource.resourcePool
  puts "using compute resource #{resource.name}"

  vm = $vmFolder.RegisterVM_Task(:path => path,
                                 :asTemplate => false,
                                 :pool => rp).wait_for_completion
  _list_vm vm
end

def extraConfig id, *args
  _extraConfig(id, *args.map { |x| /#{x}/ })
end

def setExtraConfig id, *args
  h = Hash[args.map { |x| x.split('=', 2).tap { |a| a << '' if a.size == 1 } }]
  _setExtraConfig id, h
end

def ssh id
  ip = vm_ip vm(id)
  ssh_cmd = "ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no root@#{ip}"
  system_fg(ssh_cmd)
end

def rlui id
  ip = vm_ip vm(id)

  env = Hash[%w(RBVMOMI_PASSWORD RBVMOMI_HOST RBVMOMI_USER RBVMOMI_SSL RBVMOMI_PORT
                RBVMOMI_FOLDER RBVMOMI_DATASTORE RBVMOMI_PATH RBVMOMI_DATACENTER
                RBVMOMI_COMPUTER).map { |k| [k,nil] }]
  cmd = "rlui #{ip}"
  system_fg(cmd, env)
end

def ping id
  ip = vm_ip vm(id)
  system_fg "ping #{ip}"
end

def ip *ids
  paths = %w(summary.runtime.powerState summary.guest.ipAddress summary.config.annotation)

  filters = ids.map do |id|
    $vim.propertyCollector.CreateFilter :spec => {
      :propSet => [{ :type => 'VirtualMachine', :all => false, :pathSet => paths }],
      :objectSet => [{ :obj => vm(id) }],
    }, :partialUpdates => false
  end

  ver = ''
  while not ids.empty?
    result = $vim.propertyCollector.WaitForUpdates(:version => ver)
    ver = result.version

    ids.reject! do |id|
      begin
        ip = vm_ip(vm(id))
        puts "#{vm(id).name}: #{ip}"
        true
      rescue UserError
        false
      end
    end
  end
ensure
  filters.each(&:DestroyPropertyFilter) if filters
end
