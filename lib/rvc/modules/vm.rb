include RVC::Util

def _vm(path)
  lookup(path).tap { |obj| expect obj, VIM::VirtualMachine }
end

opts :on do
  summary "Power on VMs"
  arg :path, "VirtualMachine", :multi => true
end

def on paths
  progress paths, :PowerOnVM
end

opts :off do
  summary "Power off VMs"
  arg :path, "VirtualMachine", :multi => true
end

def off paths
  progress paths, :PowerOffVM
end

opts :reset do
  summary "Reset VMs"
  arg :path, "VirtualMachine", :multi => true
end

def reset paths
  progress paths, :ResetVM
end

opts :suspend do
  summary "Suspend VMs"
  arg :path, "VirtualMachine", :multi => true
end

def suspend paths
  progress paths, :SuspendVM
end

opts :register do
  summary "Register a VM already in a datastore"
  arg :path, "RVC path to the VMX file"
  opt :resource_pool, 'Resource pool', :short => 'R', :type => :string
  opt :folder, 'VM Folder', :short => 'F', :type => :string, :default => "."
end

def register path, opts
  vmx_file = lookup(path) or err "VMX file not found"
  folder = lookup(opts[:folder]) or err "Folder not found"

  if $vim.serviceInstance.content.about.apiType == "HostAgent" or !opts[:resource_pool_given]
    rp = $vim.rootFolder.childEntity[0].hostFolder.childEntity[0].resourcePool
  else
    rp = lookup(opts[:resource_pool]) or err "resource pool not found"
    if rp.is_a? RbVmomi::VIM::ComputeResource
      rp = rp.resourcePool
    end
  end

  vm = folder.RegisterVM_Task(:path => vmx_file.datastore_path,
                              :asTemplate => false,
                              :pool => rp).wait_for_completion
end

opts :unregister do
  summary "Unregister a VM"
  arg :path, "VirtualMachine"
end

def unregister path
  _vm(path).UnregisterVM
end

opts :kill do
  summary "Power off and destroy VMs"
  arg :path, "VirtualMachine", :multi => true
end

def kill paths
  on_paths = paths.select { |x| _vm(x).summary.runtime.powerState == 'poweredOn' }
  off on_paths unless on_paths.empty?
  CMD.basic.destroy args unless args.empty?
end

opts :answer do
  summary "Answer a VM question"
  arg :path, 'VirtualMachine'
  arg :choice, "Answer ID"
end

def answer path, str
  q = _vm(path).runtime.question or err("no question to answer")
  choice = q.choice.choiceInfo.find { |x| x.label == str }
  err("invalid answer") unless choice
  _vm(path).AnswerVM :questionid => q.path, :answerChoice => choice.key
end

opts :layout do
  summary "Display info about VM files"
  arg :path, "VirtualMachine"
end

def layout path
  _vm(path).layoutEx.file.each do |f|
    puts "#{f.type}: #{f.name}"
  end
end

opts :layout do
  summary "Display info about VM devices"
  arg :path, "VirtualMachine"
end

def devices path
  devs = _vm(path).config.hardware.device
  devs.each do |dev|
    tags = []
    tags << (dev.connectable.connected ? :connected : :disconnected) if dev.props.member? :connectable
    puts "#{dev.deviceInfo.label}: #{dev.deviceInfo.summary}; #{tags * ' '}"
  end
end

opts :connect do
  summary "Connect a virtual device"
  arg :path, "VirtualMachine"
  arg :label, "Device label"
end

def connect path, label
  change_device_connectivity path, label, true
end

opts :disconnect do
  summary "Disconnect a virtual device"
  arg :path, "VirtualMachine"
  arg :label, "Device label"
end

def disconnect args
  path, label, = args
  change_device_connectivity path, label, false
end

opts :find do
  summary "Display a menu of VMX files to register"
  arg :datastore, "Path to datastore"
  opt :resource_pool, 'Resource pool', :short => 'R', :type => :string
  opt :folder, 'VM Folder', :short => 'F', :type => :string, :default => "."
end

def find datastore_path, opts
  ds = lookup(datastore_path)
  folder = lookup(opts[:folder]) or err "Folder not found"

  if $vim.serviceInstance.content.about.apiType == "HostAgent" or !opts[:resource_pool_given]
    rp = $vim.rootFolder.childEntity[0].hostFolder.childEntity[0].resourcePool
  else
    rp = lookup(opts[:resource_pool]) or err "resource pool not found"
    if rp.is_a? RbVmomi::VIM::ComputeResource
      rp = rp.resourcePool
    end
  end

  paths = find_vmx_files(ds)
  if paths.empty?
    puts "no VMX files found"
    return
  end

  puts "Select a VMX file"
  path = menu(paths) or return

  folder.RegisterVM_Task(:path => path,
                         :asTemplate => false,
                         :pool => rp).wait_for_completion
end

opts :extraConfig do
  summary "Display extraConfig options"
  arg :path, "VirtualMachine"
  arg :regex, "Regexes to filter keys", :multi => true, :required => false
end

def extraConfig path, regexes
  _extraConfig(path, *regexes.map { |x| /#{x}/ })
end

opts :setExtraConfig do
  summary "Set extraConfig options"
  arg :path, "VirtualMachine"
  arg 'key=value', "extraConfig key/value pairs", :multi => true
end

def setExtraConfig path, pairs
  h = Hash[pairs.map { |x| x.split('=', 2).tap { |a| a << '' if a.size == 1 } }]
  _setExtraConfig path, h
end

def _setExtraConfig id, hash
  cfg = {
    :extraConfig => hash.map { |k,v| { :key => k, :value => v } },
  }
  _vm(id).ReconfigVM_Task(:spec => cfg).wait_for_completion
end

def _extraConfig id, *regexes
  _vm(id).config.extraConfig.each do |h|
    if regexes.empty? or regexes.any? { |r| h[:key] =~ r }
      puts "#{h[:key]}: #{h[:value]}"
    end
  end
  nil
end

opts :ssh do
  summary "SSH to a VM"
  arg :path, "VirtualMachine"
end

def ssh path
  ip = vm_ip _vm(path)
  ssh_cmd = "ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no root@#{ip}"
  system_fg(ssh_cmd)
end

opts :rvc do
  summary "RVC to a VM"
  arg :path, "VirtualMachine"
end

def rvc path
  ip = vm_ip _vm(path)

  env = Hash[%w(RBVMOMI_PASSWORD RBVMOMI_HOST RBVMOMI_USER RBVMOMI_SSL RBVMOMI_PORT
                RBVMOMI_FOLDER RBVMOMI_DATASTORE RBVMOMI_PATH RBVMOMI_DATACENTER
                RBVMOMI_COMPUTER).map { |k| [k,nil] }]
  cmd = "rvc #{ip}"
  system_fg(cmd, env)
end

opts :ping do
  summary "Ping a VM"
  arg :path, "VirtualMachine"
end

def ping path
  ip = vm_ip _vm(path)
  system_fg "ping #{ip}"
end

opts :ip do
  summary "Wait for and display VM IP addresses"
  arg :path, "VirtualMachine", :multi => true
end

def ip paths
  props = %w(summary.runtime.powerState summary.guest.ipAddress summary.config.annotation)

  filters = paths.map do |path|
    $vim.propertyCollector.CreateFilter :spec => {
      :propSet => [{ :type => 'VirtualMachine', :all => false, :pathSet => props }],
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

opts :add_net_device do
  summary "Add a network adapter to a virtual machine"
  arg :path, "VirtualMachine"
  opt :type, "Adapter type", :default => 'e1000'
  opt :network, "Network to connect to", :default => 'VM Network'
end

def add_net_device path, opts
  vm = _vm(path)

  case opts[:type]
  when 'e1000'
    _add_net_device path, VIM::VirtualE1000, opts[:network]
  when 'vmxnet3'
    _add_net_device path, VIM::VirtualVmxnet3, opts[:network]
  else err "unknown device"
  end
end

def _add_device path, dev
  spec = {
    :deviceChange => [
      { :operation => :add, :device => dev },
    ]
  }
  _vm(path).ReconfigVM_Task(:spec => spec).wait_for_completion
end

def _add_net_device path, klass, network
  _add_device path, klass.new(
    :key => -1,
    :deviceInfo => {
      :summary => network,
      :label => `uuidgen`.chomp
    },
    :backing => VIM.VirtualEthernetCardNetworkBackingInfo(
      :deviceName => network
    ),
    :addressType => 'generated'
  )
end

opts :remove_device do
  summary "Remove a virtual device"
  arg :path, "VirtualMachine"
  arg :label, "Device label"
end

def remove_device path, label
  vm = _vm(path)
  dev = vm.config.hardware.device.find { |x| x.deviceInfo.label == label }
  err "no such device" unless dev
  spec = {
    :deviceChange => [
      { :operation => :remove, :device => dev },
    ]
  }
  vm.ReconfigVM_Task(:spec => spec).wait_for_completion
end

opts :snapshot do
  summary "Snapshot a VM"
  arg :path, "VirtualMachine"
  arg :name, "Name of new snapshot"
end

def snapshot path, name
  progress [path], :CreateSnapshot, :memory => true, :name => name, :quiesce => false
end

# TODO make fake folder
opts :snapshots do
  summary "Display VM snapshot tree"
  arg :path, "VirtualMachine"
end

def snapshots path
  vm = _vm(path)
  _display_snapshot_tree vm.snapshot.rootSnapshotList, 0
end

def _display_snapshot_tree nodes, indent
  nodes.each do |node|
    puts "#{' '*indent}#{node.name} #{node.createTime}"
    _display_snapshot_tree node.childSnapshotList, (indent+1)
  end
end

opts :revert do
  summary "Revert a VM to its current snapshot"
  arg :path, "VirtualMachine"
end

def revert path
  progress [path], :RevertToCurrentSnapshot
end

def find_vmx_files ds
  datastorePath = "[#{ds.name}] /"
  searchSpec = {
    :details => { :fileOwner => false, :fileSize => false, :fileType => true, :modification => false  },
    :query => [
      VIM::VmConfigFileQuery()
    ]
  }
  task = ds.browser.SearchDatastoreSubFolders_Task(:datastorePath => datastorePath, :searchSpec => searchSpec)

  results = task.wait_for_completion

  files = []
  results.each do |result|
    result.file.each do |file|
      files << result.folderPath + '/' + file.path
    end
  end

  files
end

def change_device_connectivity id, label, connected
  dev = vm(id).config.hardware.device.find { |x| x.deviceInfo.label == label }
  err "no such device" unless dev
  dev.connectable.connected = connected
  spec = {
    :deviceChange => [
      { :operation => :edit, :device => dev },
    ]
  }
  vm(id).ReconfigVM_Task(:spec => spec).wait_for_completion
end

def vm_ip vm
  summary = vm.summary

  err "VM is not powered on" unless summary.runtime.powerState == 'poweredOn'

  ip = if summary.guest.ipAddress and summary.guest.ipAddress != '127.0.0.1'
    summary.guest.ipAddress
  elsif note = YAML.load(summary.config.annotation) and note.is_a? Hash and note.member? 'ip'
    note['ip']
  else
    err "no IP known for this VM"
  end
end
