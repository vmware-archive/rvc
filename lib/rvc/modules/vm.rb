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

opts :on do
  summary "Power on VMs"
  arg :vm, nil, :multi => true, :lookup => VIM::VirtualMachine
end

rvc_alias :on

def on vms
  tasks vms, :PowerOnVM
end


opts :off do
  summary "Power off VMs"
  arg :vm, nil, :multi => true, :lookup => VIM::VirtualMachine
end

rvc_alias :off

def off vms
  tasks vms, :PowerOffVM
end


opts :reset do
  summary "Reset VMs"
  arg :vm, nil, :multi => true, :lookup => VIM::VirtualMachine
end

rvc_alias :reset
rvc_alias :reset, :r

def reset vms
  tasks vms, :ResetVM
end


opts :suspend do
  summary "Suspend VMs"
  arg :vm, nil, :multi => true, :lookup => VIM::VirtualMachine
end

rvc_alias :suspend
rvc_alias :suspend, :s

def suspend vms
  tasks vms, :SuspendVM
end


opts :shutdown_guest do
  summary "Shut down guest OS"
  arg :vm, nil, :multi => true, :lookup => VIM::VirtualMachine
end

def shutdown_guest vms
  vms.each(&:ShutdownGuest)
end


opts :standby_guest do
  summary "Suspend guest OS"
  arg :vm, nil, :multi => true, :lookup => VIM::VirtualMachine
end

def standby_guest vms
  vms.each(&:StandbyGuest)
end


opts :reboot_guest do
  summary "Reboot guest OS"
  arg :vm, nil, :multi => true, :lookup => VIM::VirtualMachine
end

def reboot_guest vms
  vms.each(&:RebootGuest)
end


opts :create do
  summary "Create a new VM"
  arg :name, "Destination", :lookup_parent => VIM::Folder
  opt :pool, "Resource pool", :short => 'p', :type => :string, :lookup => VIM::ResourcePool
  opt :host, "Host", :short => 'h', :type => :string, :lookup => VIM::HostSystem
  opt :datastore, "Datastore", :short => 'd', :type => :string, :lookup => VIM::Datastore
  opt :disksize, "Size in KB of primary disk (or add a unit of <M|G|T>)", :short => 's', :type => :string, :default => "4000000"
  opt :memory, "Size in MB of memory", :short => 'm', :type => :int, :default => 128
  opt :cpucount, "Number of CPUs", :short => 'c', :type => :int, :default => 1
  text <<-EOB

Example:
  vm.create -p ~foo/resourcePool/pools/prod -d ~data/bigdisk -s 10g ~vms/new

  EOB
end


def realdisksize( size )
  size.downcase!
  if size =~ /([0-9][0-9,]*)([mgt])?/i
    size = $1.delete(',').to_i
    unit = $2

    case unit
    when 'm'
      return size * 1024
    when 'g'
      return size * ( 1024 ** 2 )
    when 't'
      return size * ( 1024 ** 3 )
    when nil
      return size
    else
      err "Unknown size modifer of '#{unit}'"
    end
  else
    err "Problem with #{size}"
  end
end


def create dest, opts
  err "must specify resource pool (--pool)" unless opts[:pool]
  err "must specify datastore (--datastore)" unless opts[:datastore]
  err "memory must be a multiple of 4MB" unless opts[:memory] % 4 == 0
  vmFolder, name = *dest
  datastore_path = "[#{opts[:datastore].name}]"
  config = {
    :name => name,
    :guestId => 'otherGuest',
    :files => { :vmPathName => datastore_path },
    :numCPUs => opts[:cpucount],
    :memoryMB => opts[:memory],
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
          :key => -1,
          :backing => VIM.VirtualDiskFlatVer2BackingInfo(
            :fileName => datastore_path,
            :diskMode => :persistent,
            :thinProvisioned => true
          ),
          :controllerKey => 1000,
          :unitNumber => 0,
          :capacityInKB => realdisksize( opts[:disksize] )
        )
      }, {
        :operation => :add,
        :device => VIM.VirtualCdrom(
          :key => -2,
          :connectable => {
            :allowGuestControl => true,
            :connected => true,
            :startConnected => true,
          },
          :backing => VIM.VirtualCdromIsoBackingInfo(
            :fileName => datastore_path
          ),
          :controllerKey => 200,
          :unitNumber => 0
        )
      }, {
        :operation => :add,
        :device => VIM.VirtualE1000(
          :key => -3,
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

opts :memory do
  summary "Display info about VM devices"
  arg :vm, nil, :lookup => VIM::VirtualMachine
end

def memory vm
  ram = vm.config.hardware.memoryMB
  puts "Memory currently is #{ram}MB"
end

opts :set_memory do
  summary "Change memory on a VM"
  arg :vm, nil, :lookup => VIM::VirtualMachine
  arg :memory, "New amount of RAM in MB", :type => :int
end

def set_memory vm,memory
  err "VM needs to be off" unless vm.summary.runtime.powerState == 'poweredOff'
  err "memory must be a multiple of 4MB" unless ( memory.to_i % 4 ) == 0

  spec = { :memoryMB => memory }
  vm.ReconfigVM_Task(:spec => spec).wait_for_completion
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
  rp = opts[:resource_pool] || opts[:folder]._connection.rootFolder.childEntity[0].hostFolder.childEntity[0].resourcePool
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
  opt :resource_pool, "Resource pool", :short => 'R', :type => :string, :lookup => VIM::ResourcePool
  opt :folder, "Folder to register in", :short => 'F', :type => :string, :default => ".", :lookup => VIM::Folder
end

def find ds, opts
  folder = opts[:folder]
  rp = opts[:resource_pool] || opts[:folder]._connection.rootFolder.childEntity[0].hostFolder.childEntity[0].resourcePool

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
  arg :cmd, "Optional command", :required => false, :default => nil
  opt :login, "Username", :short => 'l', :default => 'root'
end

rvc_alias :ssh

def ssh vm, cmd, opts
  ip = vm_ip vm
  cmd_arg = cmd ? Shellwords.escape(cmd) : ""
  ssh_cmd = "ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -l #{Shellwords.escape opts[:login]} #{Shellwords.escape ip} #{cmd_arg}"
  system_fg(ssh_cmd)
end


opts :rvc do
  summary "RVC to a VM"
  arg :vm, nil, :lookup => VIM::VirtualMachine
end

rvc_alias :rvc

def rvc vm
  ip = vm_ip vm

  env = Hash[%w(RBVMOMI_PASSWORD RBVMOMI_HOST RBVMOMI_USER RBVMOMI_SSL RBVMOMI_PORT
                RBVMOMI_FOLDER RBVMOMI_DATASTORE RBVMOMI_PATH RBVMOMI_DATACENTER
                RBVMOMI_COMPUTER).map { |k| [k,nil] }]
  cmd = "rvc #{Shellwords.escape ip}"
  system_fg(cmd, env)
end


opts :ping do
  summary "Ping a VM"
  arg :vm, nil, :lookup => VIM::VirtualMachine
end

rvc_alias :ping

def ping vm
  ip = vm_ip vm
  system_fg "ping #{Shellwords.escape ip}"
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


opts :migrate do
  summary "Migrate a VM"
  arg :vm, nil, :lookup => VIM::VirtualMachine, :multi => true
  opt :pool, "Resource pool", :short => 'p', :type => :string, :lookup => VIM::ResourcePool
  opt :host, "Host", :short => 'h', :type => :string, :lookup => VIM::HostSystem
end

def migrate vms, opts
  tasks vms, :MigrateVM, :pool => opts[:pool],
                         :host => opts[:host],
                         :priority => :defaultPriority
end


opts :clone do
  summary "Clone a VM"
  arg :src, nil, :lookup => VIM::VirtualMachine
  arg :dst, "Path to new VM", :lookup_parent => VIM::Folder
  opt :pool, "Resource pool", :short => 'p', :type => :string, :lookup => VIM::ResourcePool
  opt :host, "Host", :short => 'h', :type => :string, :lookup => VIM::HostSystem
  opt :template, "Create a template", :short => 't'
  opt :linked, "Create a linked clone", :short => 'l'
  opt :powerOn, "Power on VM after clone"
end

def clone src, dst, opts
  folder, name = *dst
  diskMoveType = nil

  if opts[:linked]
    deltaize_disks src
    diskMoveType = :moveChildMostDiskBacking
  end

  task = src.CloneVM_Task(:folder => folder,
                          :name => name,
                          :spec => {
                            :location => {
                              :diskMoveType => diskMoveType,
                              :host => opts[:host],
                              :pool => opts[:pool],
                            },
                            :template => opts[:template],
                            :powerOn => opts[:powerOn],
                          })
  progress [task]
end


def deltaize_disks vm
  real_disks = vm.config.hardware.device.grep(VIM::VirtualDisk).select { |x| x.backing.parent == nil }
  unless real_disks.empty?
    puts "Reconfiguring source VM to use delta disks..."
    deviceChange = []
    real_disks.each do |disk|
      deviceChange << { :operation => :remove, :device => disk }
      deviceChange << {
        :operation => :add,
        :fileOperation => :create,
        :device => disk.dup.tap { |x|
          x.backing = x.backing.dup
          x.backing.fileName = "[#{disk.backing.datastore.name}]"
          x.backing.parent = disk.backing
        }
      }
    end
    progress [vm.ReconfigVM_Task(:spec => { :deviceChange => deviceChange })]
  end
end


opts :annotate do
  summary "Change a VM's annotation"
  arg :vm, nil, :lookup => VIM::VirtualMachine
  arg :annotation, nil
end

def annotate vm, str
  vm.ReconfigVM_Task(:spec => { :annotation => str }).wait_for_completion
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
      files << "#{result.folderPath}/#{file.path}"
    end
  end

  files
end

def change_device_connectivity vm, label, connected
  dev = vm.config.hardware.device.find { |x| x.deviceInfo.label == label }
  err "no such device" unless dev
  dev.connectable.connected = connected
  spec = {
    :deviceChange => [
      { :operation => :edit, :device => dev },
    ]
  }
  vm.ReconfigVM_Task(:spec => spec).wait_for_completion
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
