include RVC::Util

opts :on do
  summary "Power on VMs"
  arg :vm, nil, :multi => true, :lookup => VIM::VirtualMachine
end

rvc_alias :on

def on vms
  progress vms, :PowerOnVM
end


opts :off do
  summary "Power off VMs"
  arg :vm, nil, :multi => true, :lookup => VIM::VirtualMachine
end

rvc_alias :off

def off vms
  progress vms, :PowerOffVM
end


opts :reset do
  summary "Reset VMs"
  arg :vm, nil, :multi => true, :lookup => VIM::VirtualMachine
end

rvc_alias :reset
rvc_alias :reset, :r

def reset vms
  progress vms, :ResetVM
end


opts :suspend do
  summary "Suspend VMs"
  arg :vm, nil, :multi => true, :lookup => VIM::VirtualMachine
end

rvc_alias :suspend
rvc_alias :suspend, :s

def suspend vms
  progress vms, :SuspendVM
end


opts :create do
  summary "Create a new VM"
  arg :name, "Name"
  opt :pool, nil, :short => 'p', :type => :string, :lookup => VIM::ResourcePool
  opt :host, nil, :short => 'h', :type => :string, :lookup => VIM::HostSystem
  opt :datastore, nil, :short => 'd', :type => :string, :lookup => VIM::Datastore
end

def create name, opts
  err "must specify resource pool (--pool)" unless opts[:pool]
  err "must specify datastore (--datastore)" unless opts[:datastore]
  vmFolder = lookup!(File.dirname(name), VIM::Folder)
  datastore_path = "[#{opts[:datastore].name}]"
  config = {
    :name => File.basename(name),
    :guestId => 'otherGuest',
    :files => { :vmPathName => datastore_path },
    :numCPUs => 1,
    :memoryMB => 128,
    :deviceChange => [
      {
        :operation => :add,
        :device => VIM.VirtualLsiLogicController(
          :key => 1000,
          :busNumber => 0,
          :sharedBus => :noSharing
        )
      }, {
        :operation => :add,
        :fileOperation => :create,
        :device => VIM.VirtualDisk(
          :key => 0,
          :backing => VIM.VirtualDiskFlatVer2BackingInfo(
            :fileName => datastore_path,
            :diskMode => :persistent,
            :thinProvisioned => true
          ),
          :controllerKey => 1000,
          :unitNumber => 0,
          :capacityInKB => 4000000
        )
      }, {
        :operation => :add,
        :device => VIM.VirtualCdrom(
          :key => 0,
          :connectable => {
            :allowGuestControl => true,
            :connected => true,
            :startConnected => true,
          },
          :backing => VIM.VirtualCdromIsoBackingInfo(
            :fileName => datastore_path,
          ),
          :controllerKey => 200,
          :unitNumber => 0
        )
      }, {
        :operation => :add,
        :device => VIM.VirtualE1000(
          :key => 0,
          :deviceInfo => {
            :label => 'Network Adapter 1',
            :summary => 'VM Network'
          },
          :backing => VIM.VirtualEthernetCardNetworkBackingInfo(
            :deviceName => 'VM Network'
          ),
          :addressType => 'generated'
        )
      }
    ],
  }
  vmFolder.CreateVM_Task(:config => config,
                         :pool => opts[:pool],
                         :host => opts[:host]).wait_for_completion
end


opts :insert_cdrom do
  summary "Put a disc in a virtual CDROM drive"
  arg :vm, nil, :lookup => VIM::VirtualMachine
  arg :iso, "Path to the ISO image on a datastore", :lookup => VIM::Datastore::FakeDatastoreFile
end

def insert_cdrom vm, iso
  device = vm.config.hardware.device.grep(VIM::VirtualCdrom)[0]
  err "No virtual CDROM drive found" unless device

  device.backing = VIM.VirtualCdromIsoBackingInfo(:fileName => iso.datastore_path)

  spec = {
    :deviceChange => [
      {
        :operation => :edit,
        :device => device
      }
    ]
  }
  
  vm.ReconfigVM_Task(:spec => spec)
end

opts :register do
  summary "Register a VM already in a datastore"
  arg :file, "RVC path to the VMX file", :lookup => VIM::Datastore::FakeDatastoreFile
  opt :resource_pool, 'Resource pool', :short => 'R', :type => :string, :lookup => VIM::ResourcePool
  opt :folder, 'VM Folder', :short => 'F', :default => ".", :lookup => VIM::Folder
end

def register vmx_file, opts
  rp = opts[:resourcePool] || opts[:folder]._connection.rootFolder.childEntity[0].hostFolder.childEntity[0].resourcePool
  vm = opts[:folder].RegisterVM_Task(:path => vmx_file.datastore_path,
                                     :asTemplate => false,
                                     :pool => rp).wait_for_completion
end


opts :unregister do
  summary "Unregister a VM"
  arg :vm, nil, :lookup => VIM::VirtualMachine
end

def unregister vm
  vm.UnregisterVM
end


opts :kill do
  summary "Power off and destroy VMs"
  arg :vm, nil, :multi => true, :lookup => VIM::VirtualMachine
end

rvc_alias :kill
rvc_alias :kill, :k

def kill vms
  on_vms = vms.select { |x| x.summary.runtime.powerState == 'poweredOn' }
  off on_vms unless on_vms.empty?
  CMD.basic.destroy vms unless vms.empty?
end


opts :answer do
  summary "Answer a VM question"
  arg :vm, nil, :lookup => VIM::VirtualMachine
  arg :choice, "Answer ID"
end

def answer vm, str
  choice = q.choice.choiceInfo.find { |x| x.label == str }
  err("invalid answer") unless choice
  vm.AnswerVM :questionid => q.path, :answerChoice => choice.key
end


opts :layout do
  summary "Display info about VM files"
  arg :vm, nil, :lookup => VIM::VirtualMachine
end

def layout vm
  vm.layoutEx.file.each do |f|
    puts "#{f.type}: #{f.name}"
  end
end


opts :devices do
  summary "Display info about VM devices"
  arg :vm, nil, :lookup => VIM::VirtualMachine
end

def devices vm
  devs = vm.config.hardware.device
  devs.each do |dev|
    tags = []
    tags << (dev.connectable.connected ? :connected : :disconnected) if dev.props.member? :connectable
    puts "#{dev.deviceInfo.label} (#{dev.class}): #{dev.deviceInfo.summary}; #{tags * ' '}"
  end
end


opts :connect do
  summary "Connect a virtual device"
  arg :vm, nil, :lookup => VIM::VirtualMachine
  arg :label, "Device label"
end

def connect vm, label
  change_device_connectivity vm, label, true
end


opts :disconnect do
  summary "Disconnect a virtual device"
  arg :vm, nil, :lookup => VIM::VirtualMachine
  arg :label, "Device label"
end

def disconnect vm, label
  change_device_connectivity vm, label, false
end


opts :find do
  summary "Display a menu of VMX files to register"
  arg :datastore, nil, :lookup => VIM::Datastore
  opt :resource_pool, nil, :short => 'R', :type => :string, :lookup => VIM::ResourcePool
  opt :folder, nil, :short => 'F', :type => :string, :default => ".", :lookup => VIM::Folder
end

def find ds, opts
  folder = opts[:folder]
  rp = opts[:resourcePool] || opts[:folder]._connection.rootFolder.childEntity[0].hostFolder.childEntity[0].resourcePool

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
  arg :vm, nil, :lookup => VIM::VirtualMachine
  arg :regex, "Regexes to filter keys", :multi => true, :required => false
end

def extraConfig vm, regexes
  _extraConfig(vm, *regexes.map { |x| /#{x}/ })
end


opts :setExtraConfig do
  summary "Set extraConfig options"
  arg :vm, nil, :lookup => VIM::VirtualMachine
  arg 'key=value', "extraConfig key/value pairs", :multi => true
end

def setExtraConfig vm, pairs
  h = Hash[pairs.map { |x| x.split('=', 2).tap { |a| a << '' if a.size == 1 } }]
  _setExtraConfig vm, h
end


def _setExtraConfig vm, hash
  cfg = {
    :extraConfig => hash.map { |k,v| { :key => k, :value => v } },
  }
  vm.ReconfigVM_Task(:spec => cfg).wait_for_completion
end

def _extraConfig vm, *regexes
  vm.config.extraConfig.each do |h|
    if regexes.empty? or regexes.any? { |r| h[:key] =~ r }
      puts "#{h[:key]}: #{h[:value]}"
    end
  end
  nil
end


opts :ssh do
  summary "SSH to a VM"
  arg :vm, nil, :lookup => VIM::VirtualMachine
end

rvc_alias :ssh

def ssh vm
  ip = vm_ip vm
  ssh_cmd = "ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no root@#{ip}"
  system_fg(ssh_cmd)
end


opts :rvc do
  summary "RVC to a VM"
  arg :vm, nil, :lookup => VIM::VirtualMachine
end

def rvc vm
  ip = vm_ip vm

  env = Hash[%w(RBVMOMI_PASSWORD RBVMOMI_HOST RBVMOMI_USER RBVMOMI_SSL RBVMOMI_PORT
                RBVMOMI_FOLDER RBVMOMI_DATASTORE RBVMOMI_PATH RBVMOMI_DATACENTER
                RBVMOMI_COMPUTER).map { |k| [k,nil] }]
  cmd = "rvc #{ip}"
  system_fg(cmd, env)
end


opts :ping do
  summary "Ping a VM"
  arg :vm, nil, :lookup => VIM::VirtualMachine
end

rvc_alias :ping

def ping vm
  ip = vm_ip vm
  system_fg "ping #{ip}"
end


opts :ip do
  summary "Wait for and display VM IP addresses"
  arg :vm, nil, :lookup => VIM::VirtualMachine, :multi => true
end

def ip vms
  props = %w(summary.runtime.powerState summary.guest.ipAddress summary.config.annotation)
  connection = single_connection vms

  filters = vms.map do |vm|
    connection.propertyCollector.CreateFilter :spec => {
      :propSet => [{ :type => 'VirtualMachine', :all => false, :pathSet => props }],
      :objectSet => [{ :obj => vm }],
    }, :partialUpdates => false
  end

  ver = ''
  while not vms.empty?
    result = connection.propertyCollector.WaitForUpdates(:version => ver)
    ver = result.version

    vms.reject! do |vm|
      begin
        ip = vm_ip(vm)
        puts "#{vm.name}: #{ip}"
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
  arg :vm, nil, :lookup => VIM::VirtualMachine
  opt :type, "Adapter type", :default => 'e1000'
  opt :network, "Network to connect to", :default => 'VM Network'
end

def add_net_device vm, opts
  case opts[:type]
  when 'e1000'
    _add_net_device vm, VIM::VirtualE1000, opts[:network]
  when 'vmxnet3'
    _add_net_device vm, VIM::VirtualVmxnet3, opts[:network]
  else err "unknown device"
  end
end


def _add_device vm, dev
  spec = {
    :deviceChange => [
      { :operation => :add, :device => dev },
    ]
  }
  vm.ReconfigVM_Task(:spec => spec).wait_for_completion
end

def _add_net_device vm, klass, network
  _add_device vm, klass.new(
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
  arg :vm, nil, :lookup => VIM::VirtualMachine
  arg :label, "Device label"
end

def remove_device vm, label
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
  arg :vm, nil, :lookup => VIM::VirtualMachine
  arg :name, "Name of new snapshot"
end

def snapshot vm, name
  progress [vm], :CreateSnapshot, :memory => true, :name => name, :quiesce => false
end


# TODO make fake folder
opts :snapshots do
  summary "Display VM snapshot tree"
  arg :vm, nil, :lookup => VIM::VirtualMachine
end

def snapshots vm
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
  arg :vm, nil, :lookup => VIM::VirtualMachine
end

def revert vm
  progress [vm], :RevertToCurrentSnapshot
end


opts :migrate do
  summary "Migrate a VM"
  arg :vm, nil, :lookup => VIM::VirtualMachine
  opt :pool, nil, :short => 'p', :type => :string, :lookup => VIM::ResourcePool
  opt :host, nil, :short => 'h', :type => :string, :lookup => VIM::HostSystem
end

def migrate vm, opts
  progress [vm], :MigrateVM, :pool => opts[:pool],
                             :host => opts[:host],
                             :priority => :defaultPriority
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
