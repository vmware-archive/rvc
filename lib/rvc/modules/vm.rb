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

require 'rvc/vim'
VIM::Datastore

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


opts :wait_for_shutdown do
  summary "Waits for a VM to shutdown"
  arg :vm, nil, :multi => true, :lookup => VIM::VirtualMachine
  opt :timeout, "Timeout in seconds", :type => :int, :default => 300
  opt :delay, "Interval in seconds", :type => :int, :default => 5
end

def wait_for_shutdown vms, opts
  finish_time = Time.now + opts[:timeout]
  while Time.now < finish_time
    all_off = true
    vms.each do |vm|
      if vm.summary.runtime.powerState == 'poweredOn'
        all_off = false
      end
    end
    return if all_off
    sleep [opts[:delay], finish_time - Time.now].min
  end
  puts "WARNING: At least one VM did not shut down!"
end


opts :shutdown_guest do
  summary "Shut down guest OS"
  arg :vm, nil, :multi => true, :lookup => VIM::VirtualMachine
  opt :timeout, "Timeout for guest shut down in seconds", :type => :int, :default => nil
  opt :delay, "Interval between checks for guest shut down in seconds", :type => :int, :default => nil
end

def shutdown_guest vms, opts
  vms.each(&:ShutdownGuest)
  wait_for_shutdown vms, opts unless opts[:timeout].nil?
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
  opt :host, "Host", :short => 'o', :type => :string, :lookup => VIM::HostSystem
  opt :datastore, "Datastore", :short => 'd', :type => :string, :lookup => VIM::Datastore
  opt :memory, "Size in MB of memory", :short => 'm', :type => :int, :default => 128
  opt :cpus, "Number of CPUs", :short => 'c', :type => :int, :default => 1
  opt :guest_id, "Guest OS", :short => 'g', :default => "otherGuest" # XXX tab complete

  text <<-EOB

  No disks or network adapters are initially present. Use device.add_disk and
  device.add_net to do this.

Example:
  vm.create ~/vm/foo --pool ~/host/my_cluster/resourcePool --datastore ~/datastore/my_datastore
  device.add_disk ~/vm/foo -s 30G
  device.add_net ~/vm/foo ~/network/VM\\ Network
  EOB
end


def create dest, opts
  err "must specify resource pool (--pool)" unless opts[:pool]
  err "must specify datastore (--datastore)" unless opts[:datastore]
  err "memory must be a multiple of 4MB" unless opts[:memory] % 4 == 0
  vmFolder, name = *dest
  datastore_path = "[#{opts[:datastore].name}]"
  config = {
    :name => name,
    :guestId => opts[:guest_id],
    :files => { :vmPathName => datastore_path },
    :numCPUs => opts[:cpucount],
    :memoryMB => opts[:memory],
    :deviceChange => [
      {
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
      }
    ],
  }
  vmFolder.CreateVM_Task(:config => config,
                         :pool => opts[:pool],
                         :host => opts[:host]).wait_for_completion
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

opts :bootconfig do
  summary "Alter the boot config settings"
  arg :vm, nil, :lookup => VIM::VirtualMachine
  opt :delay, "Time in milliseconds to delay boot", :short => 'd', :type => :int
  opt :enablebootretry,  "Enable rebooting if no boot device found", :short => 'r'
  opt :disablebootretry, "Disable rebooting if no boot device found"
  opt :retrydelay, "Time to wait before rebooting to retry", :short => 't', :type => :int
  opt :show, "Show the current bootoptions", :short => 's'
  conflicts :enablebootretry, :disablebootretry   # not that this currently works nicely, but still.
end

def bootconfig vm, opts

  if opts[:show]
    pp vm.config.bootOptions
    return
  end

  cur_delay        = vm.config.bootOptions.bootDelay
  cur_retrydelay   = vm.config.bootOptions.bootRetryDelay
  cur_retryenabled = vm.config.bootOptions.bootRetryEnabled

  if opts[:delay] and opts[:delay] != cur_delay
    new_delay = opts[:delay]
  else
    new_delay = cur_delay
  end

  if opts[:retrydelay] and opts[:retrydelay] != cur_retrydelay
    new_retrydelay = opts[:retrydelay]
    new_retryenabled = true
  else
    new_retrydelay = cur_retrydelay
  end

  if opts[:enablebootretry]
    new_retryenabled = true
  elsif opts[:disablebootretry]
    new_retryenabled = false
  else
    new_retryenabled = cur_retryenabled
  end

  spec = { :bootOptions => {
    :bootDelay => new_delay,
    :bootRetryDelay => new_retrydelay,
    :bootRetryEnabled => new_retryenabled,
    }
  }

  vm.ReconfigVM_Task(:spec => spec).wait_for_completion
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
  shell.cmds.basic.destroy vms unless vms.empty?
end

opts :answer do
  summary "Answer a VM question"
  arg :choice, "Answer ID"
  arg :vm, nil, :lookup => VIM::VirtualMachine, :multi => true
end

def answer str, vms
  vms.each do |vm|
    begin
      if q = vm.runtime.question
        choice = q.choice.choiceInfo.find { |x| x.label == str }
        err("invalid answer") unless choice
        vm.AnswerVM :questionId => q.id, :answerChoice => choice.key
      end
    rescue
      puts "#{vm.name rescue vm}: #{$!.message}"
    end
  end
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


opts :extra_config do
  summary "Display extraConfig options"
  arg :vm, nil, :lookup => VIM::VirtualMachine
  arg :regex, "Regexes to filter keys", :multi => true, :required => false
end

def extra_config vm, regexes
  _extra_config(vm, *regexes.map { |x| /#{x}/ })
end


opts :set_extra_config do
  summary "Set extraConfig options"
  arg :vm, nil, :lookup => VIM::VirtualMachine
  arg 'key=value', "extraConfig key/value pairs", :multi => true
end

def set_extra_config vm, pairs
  h = Hash[pairs.map { |x| x.split('=', 2).tap { |a| a << '' if a.size == 1 } }]
  _set_extra_config vm, h
end


def _set_extra_config vm, hash
  cfg = {
    :extraConfig => hash.map { |k,v| { :key => k, :value => v } },
  }
  vm.ReconfigVM_Task(:spec => cfg).wait_for_completion
end

def _extra_config vm, *regexes
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
  opt :user, "Username", :type => :string
end

rvc_alias :rvc

def rvc vm, opts
  ip = vm_ip vm

  env = Hash[%w(RBVMOMI_PASSWORD RBVMOMI_HOST RBVMOMI_USER RBVMOMI_SSL RBVMOMI_PORT
                RBVMOMI_FOLDER RBVMOMI_DATASTORE RBVMOMI_PATH RBVMOMI_DATACENTER
                RBVMOMI_COMPUTER).map { |k| [k,nil] }]
  cmd = "rvc #{opts[:user] && Shellwords.escape("#{opts[:user]}@")}#{Shellwords.escape ip}"
  system_fg(cmd, env)
end

opts :rdp do
  summary "Connect via RDP"
  arg :vms, nil, :lookup => VIM::VirtualMachine, :multi => true
  opt :resolution, "Desired resolution", :type => :string, :default => ($rdpResolution ? $rdpResolution : '1024x768')
  opt :username, "Username", :type => :string, :default => 'Administrator'
  opt :password, "Password", :type => :string, :default => ($rdpDefaultPassword ? $rdpDefaultPassword : '')
end

rvc_alias :rdp, :rdp

def rdp vms, h
  resolution = h[:resolution]
  if !resolution
    resolution = $rdpResolution ? $rdpResolution : '1024x768'  
  end
  vms.each do |vm|
    ip = vm_ip vm

    begin
      timeout(1) { TCPSocket.new ip, 3389; up = true }
    rescue
      puts "#{vm.name}: Warning: Looks like the RDP port is not responding"
    end
    
    cmd = "rdesktop -u '#{h[:username]}' -p '#{h[:password]}' -g#{resolution} #{ip} >/dev/null 2>&1 &"
    system(cmd)
  end
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


opts :migrate do
  summary "Migrate a VM"
  arg :vm, nil, :lookup => VIM::VirtualMachine, :multi => true
  opt :pool, "Resource pool", :short => 'p', :type => :string, :lookup => VIM::ResourcePool
  opt :host, "Host", :short => 'o', :type => :string, :lookup => VIM::HostSystem
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
  opt :host, "Host", :short => 'o', :type => :string, :lookup => VIM::HostSystem
  opt :template, "Create a template", :short => 't'
  opt :linked, "Create a linked clone", :short => 'l'
  opt :power_on, "Power on VM after clone"
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
                            :powerOn => opts[:power_on],
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


opts :modify_cpu do
  summary "Change CPU configuration"
  arg :vm, nil, :lookup => VIM::VirtualMachine
  opt :num, "New number of CPUs", :type => :int, :required => true
end

def modify_cpu vm, opts
  spec = { :numCPUs => opts[:num] }
  tasks [vm], :ReconfigVM, :spec => spec
end


opts :modify_memory do
  summary "Change memory configuration"
  arg :vm, nil, :lookup => VIM::VirtualMachine
  opt :size, "New memory size in MB", :type => :int, :required => true
end

def modify_memory vm, opts
  err "VM needs to be off" unless vm.summary.runtime.powerState == 'poweredOff'
  err "memory must be a multiple of 4MB" unless ( opts[:size]  % 4 ) == 0
  spec = { :memoryMB => opts[:size] }
  tasks [vm], :ReconfigVM, :spec => spec
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
