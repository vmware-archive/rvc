include RVC::Util

def _vm(path)
  lookup(path).tap { |obj| expect obj, VIM::VirtualMachine }
end

opts :on do
  text "Power on VMs"
end

def on *paths
  progress paths, :PowerOnVM
end

def off *paths
  progress paths, :PowerOffVM
end

def reset *paths
  progress paths, :ResetVM
end

def suspend *paths
  progress paths, :SuspendVM
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

def kill *paths
  on_paths = paths.select { |x| _vm(x).summary.runtime.powerState == 'poweredOn' }
  off *on_paths unless on_paths.empty?
  CMD.basic.destroy *paths unless paths.empty?
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

def rvc path
  ip = vm_ip _vm(path)

  env = Hash[%w(RBVMOMI_PASSWORD RBVMOMI_HOST RBVMOMI_USER RBVMOMI_SSL RBVMOMI_PORT
                RBVMOMI_FOLDER RBVMOMI_DATASTORE RBVMOMI_PATH RBVMOMI_DATACENTER
                RBVMOMI_COMPUTER).map { |k| [k,nil] }]
  cmd = "rvc #{ip}"
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

opts :add_net_device do
  text "Add a network adapter to a virtual machine"
  opt :type, "Adapter type", :default => 'e1000'
  opt :network, "Network to connect to", :default => 'VM Network'
end

def add_net_device argv, opts
  path = argv[0] or err("VM path required")
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

def snapshot path, name
  progress [path], :CreateSnapshot, :memory => true, :name => name, :quiesce => false
end

# TODO make fake folder
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

def revert path
  progress [path], :RevertToCurrentSnapshot
end
