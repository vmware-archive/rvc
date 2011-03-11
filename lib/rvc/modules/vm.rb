include RVC::Util

def _vm(path)
  lookup(path).tap { |obj| expect obj, VIM::VirtualMachine }
end

opts :on do
  summary "Power on VMs"
  usage "path..."
end

def on args
  progress args, :PowerOnVM
end

opts :off do
  summary "Power off VMs"
  usage "path..."
end

def off args
  progress args, :PowerOffVM
end

opts :reset do
  summary "Reset VMs"
  usage "path..."
end

def reset args
  progress args, :ResetVM
end

opts :suspend do
  summary "Suspend VMs"
  usage "path..."
end

def suspend args
  progress args, :SuspendVM
end

opts :register do
  summary "Register a VM already in a datastore"
  usage "datastore filename"
end

def register args
  datastore, path, = args
  path = "#{path}/#{path}.vmx" unless path =~ /\.vmx$/
  ds_path = "[#{datastore}] #{path}"

  resource = $dc.hostFolder.childEntity.first
  rp = resource.resourcePool
  puts "using compute resource #{resource.name}"
  vm = $context.cur.RegisterVM_Task(:path => ds_path,
                                    :asTemplate => false,
                                    :pool => rp).wait_for_completion
end

opts :unregister do
  summary "Unregister a VM"
  usage "path"
end

def unregister args
  path, = args
  _vm(path).UnregisterVM
end

opts :kill do
  summary "Power off and destroy VMs"
  usage "path..."
end

def kill args
  on_paths = args.select { |x| _vm(x).summary.runtime.powerState == 'poweredOn' }
  off *on_paths unless on_paths.empty?
  CMD.basic.destroy *paths unless paths.empty?
end

opts :answer do
  summary "Answer a VM question"
  usage "path choice"
end

def answer args
  path, str, = args
  q = _vm(path).runtime.question or err("no question to answer")
  choice = q.choice.choiceInfo.find { |x| x.label == str }
  err("invalid answer") unless choice
  _vm(path).AnswerVM :questionid => q.path, :answerChoice => choice.key
end

opts :layout do
  summary "Display info about VM files"
  usage "path"
end

def layout args
  path, = args
  _vm(path).layoutEx.file.each do |f|
    puts "#{f.type}: #{f.name}"
  end
end

opts :layout do
  summary "Display info about VM devices"
  usage "path"
end

def devices args
  path, = args
  devs = _vm(path).config.hardware.device
  devs.each do |dev|
    tags = []
    tags << (dev.connectable.connected ? :connected : :disconnected) if dev.props.member? :connectable
    puts "#{dev.deviceInfo.label}: #{dev.deviceInfo.summary}; #{tags * ' '}"
  end
end

opts :connect do
  summary "Connect a virtual device"
  usage "path label"
end

def connect args
  path, label, = args
  change_device_connectivity path, label, true
end

opts :disconnect do
  summary "Disconnect a virtual device"
  usage "path label"
end

def disconnect args
  path, label, = args
  change_device_connectivity path, label, false
end

# TODO move to datastore?
opts :find do
  summary "Display a menu of VMX files to register"
  usage "[datastore]"
end

def find args
  datastore_name, = args
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

  vm = $context.cur.RegisterVM_Task(:path => path,
                                    :asTemplate => false,
                                    :pool => rp).wait_for_completion
end

opts :extraConfig do
  summary "Display extraConfig options"
  usage "path regex..."
end

def extraConfig args
  path, *regexes = args
  _extraConfig(path, *regexes.map { |x| /#{x}/ })
end

opts :setExtraConfig do
  summary "Set extraConfig options"
  usage "path key=value..."
end

def setExtraConfig args
  path, *pairs = args
  h = Hash[pairs.map { |x| x.split('=', 2).tap { |a| a << '' if a.size == 1 } }]
  _setExtraConfig path, h
end

opts :ssh do
  summary "SSH to a VM"
  usage "path"
end

def ssh args
  path, = args
  ip = vm_ip _vm(path)
  ssh_cmd = "ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no root@#{ip}"
  system_fg(ssh_cmd)
end

opts :rvc do
  summary "RVC to a VM"
  usage "path"
end

def rvc args
  path, = args
  ip = vm_ip _vm(path)

  env = Hash[%w(RBVMOMI_PASSWORD RBVMOMI_HOST RBVMOMI_USER RBVMOMI_SSL RBVMOMI_PORT
                RBVMOMI_FOLDER RBVMOMI_DATASTORE RBVMOMI_PATH RBVMOMI_DATACENTER
                RBVMOMI_COMPUTER).map { |k| [k,nil] }]
  cmd = "rvc #{ip}"
  system_fg(cmd, env)
end

opts :ping do
  summary "Ping a VM"
  usage "path"
end

def ping args
  path, = args
  ip = vm_ip _vm(path)
  system_fg "ping #{ip}"
end

opts :ip do
  summary "Wait for and display VM IP addresses"
  usage "path..."
end

def ip args
  paths = args
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
  usage "path [opts]"
  opt :type, "Adapter type", :default => 'e1000'
  opt :network, "Network to connect to", :default => 'VM Network'
end

def add_net_device args, opts
  path = args[0] or err("VM path required")
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
  usage "path label"
end

def remove_device args
  path, label, = args
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
  usage "path name"
end

def snapshot args
  path, name, = args
  progress [path], :CreateSnapshot, :memory => true, :name => name, :quiesce => false
end

# TODO make fake folder
opts :snapshots do
  summary "Display VM snapshot tree"
  usage "path"
end

def snapshots args
  path, = args
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
  summary "Revert VM to its current snapshot"
  usage "path"
end

def revert args
  path, = args
  progress [path], :RevertToCurrentSnapshot
end
