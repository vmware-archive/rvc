include RLUI::Util

def _vm(path)
  lookup(path).tap { |obj| expect obj, VIM::VirtualMachine }
end

def on *paths
  vmtask paths, :PowerOnVM
end

def off *paths
  vmtask paths, :PowerOffVM
end

def reset *paths
  vmtask paths, :ResetVM
end

def suspend *paths
  vmtask paths, :SuspendVM
end

def register datastore, path
  path = "#{path}/#{path}.vmx" unless path =~ /\.vmx$/
  ds_path = "[#{datastore}] #{path}"

  resource = $dc.hostFolder.childEntity.first
  rp = resource.resourcePool
  puts "using compute resource #{resource.name}"
  vm = MODES[:vm].cur.RegisterVM_Task(:path => ds_path,
                                      :asTemplate => false,
                                      :pool => rp).wait_for_completion
end

def unregister path
  _vm(path).UnregisterVM
end

def destroy *paths
  vmtask paths, :Destroy
end

def kill *paths
  on_paths = paths.select { |x| _vm(x).summary.runtime.powerState == 'poweredOn' }
  off *on_paths unless on_paths.empty?
  destroy *paths unless paths.empty?
end

def info path
  config, runtime, guest = _vm(path).collect :config, :runtime, :guest

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

def answer path, str
  q = _vm(path).runtime.question or err("no question to answer")
  choice = q.choice.choiceInfo.find { |x| x.label == str }
  err("invalid answer") unless choice
  _vm(path).AnswerVM :questionid => q.path, :answerChoice => choice.key
end

def layout path
  _vm(path).layoutEx.file.each do |f|
    puts "#{f.type}: #{f.name}"
  end
end

def devices path
  devs = _vm(path).config.hardware.device
  devs.each do |dev|
    tags = []
    tags << (dev.connectable.connected ? :connected : :disconnected) if dev.props.member? :connectable
    puts "#{dev.deviceInfo.label}: #{dev.deviceInfo.summary}; #{tags * ' '}"
  end
end

def connect path, label
  change_device_connectivity path, label, true
end

def disconnect path, label
  change_device_connectivity path, label, false
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

  vm = MODES[:vm].cur.RegisterVM_Task(:path => path,
                                      :asTemplate => false,
                                      :pool => rp).wait_for_completion
end

def extraConfig path, *args
  _extraConfig(path, *args.map { |x| /#{x}/ })
end

def setExtraConfig path, *args
  h = Hash[args.map { |x| x.split('=', 2).tap { |a| a << '' if a.size == 1 } }]
  _setExtraConfig path, h
end

def ssh path
  ip = vm_ip _vm(path)
  ssh_cmd = "ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no root@#{ip}"
  system_fg(ssh_cmd)
end

def rlui path
  ip = vm_ip _vm(path)

  env = Hash[%w(RBVMOMI_PASSWORD RBVMOMI_HOST RBVMOMI_USER RBVMOMI_SSL RBVMOMI_PORT
                RBVMOMI_FOLDER RBVMOMI_DATASTORE RBVMOMI_PATH RBVMOMI_DATACENTER
                RBVMOMI_COMPUTER).map { |k| [k,nil] }]
  cmd = "rlui #{ip}"
  system_fg(cmd, env)
end

def ping path
  ip = vm_ip _vm(path)
  system_fg "ping #{ip}"
end

def ip *paths
  paths = %w(summary.runtime.powerState summary.guest.ipAddress summary.config.annotation)

  filters = paths.map do |path|
    $vim.propertyCollector.CreateFilter :spec => {
      :propSet => [{ :type => 'VirtualMachine', :all => false, :pathSet => paths }],
      :objectSet => [{ :obj => _vm(path) }],
    }, :partialUpdates => false
  end

  ver = ''
  while not paths.empty?
    result = $vim.propertyCollector.WaitForUpdates(:version => ver)
    ver = result.version

    paths.reject! do |path|
      begin
        ip = vm_ip(_vm(path))
        puts "#{_vm(path).name}: #{ip}"
        true
      rescue UserError
        false
      end
    end
  end
ensure
  filters.each(&:DestroyPropertyFilter) if filters
end
