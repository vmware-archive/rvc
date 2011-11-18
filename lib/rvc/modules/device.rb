opts :connect do
  summary "Connect a virtual device"
  arg :device, nil, :lookup => VIM::VirtualDevice, :multi => true
end

def connect devs
  change_devices_connectivity devs, true
end


opts :disconnect do
  summary "Disconnect a virtual device"
  arg :device, nil, :lookup => VIM::VirtualDevice, :multi => true
end

def disconnect devs
  change_devices_connectivity devs, false
end


opts :remove do
  summary "Remove a virtual device"
  arg :device, nil, :lookup => VIM::VirtualDevice, :multi => true
end

def remove devs
  vm_devs = devs.group_by(&:rvc_vm)
  tasks = vm_devs.map do |vm,my_devs|
    device_changes = my_devs.map do |dev|
      fileOp = dev.backing.is_a?(VIM::VirtualDeviceFileBackingInfo) ? 'destroy' : nil
      { :operation => :remove, :fileOperation => fileOp, :device => dev }
    end
    spec = { :deviceChange => device_changes }
    vm.ReconfigVM_Task(:spec => spec)
  end

  progress tasks
end


opts :add_net do
  summary "Add a network adapter to a virtual machine"
  arg :vm, nil, :lookup => VIM::VirtualMachine
  arg :network, nil, :lookup => VIM::Network
  opt :type, "Adapter type", :default => 'e1000'
end

NET_DEVICE_CLASSES = {
  'e1000' => VIM::VirtualE1000,
  'vmxnet3' => VIM::VirtualVmxnet3,
}

def add_net vm, network, opts
  klass = NET_DEVICE_CLASSES[opts[:type]] or err "unknown network adapter type #{opts[:type].inspect}"

  case network
  when VIM::DistributedVirtualPortgroup
    switch, pg_key = network.collect 'config.distributedVirtualSwitch', 'key'
    port = VIM.DistributedVirtualSwitchPortConnection(
      :switchUuid => switch.uuid,
      :portgroupKey => pg_key)
    summary = network.name
    backing = VIM.VirtualEthernetCardDistributedVirtualPortBackingInfo(:port => port)
  when VIM::Network
    summary = network.name
    backing = VIM.VirtualEthernetCardNetworkBackingInfo(:deviceName => network.name)
  else fail
  end

  _add_device vm, nil, klass.new(
    :key => -1,
    :deviceInfo => {
      :summary => summary,
      :label => `uuidgen`.chomp
    },
    :backing => backing,
    :addressType => 'generated'
  )
end


opts :add_disk do
  summary "Add a hard drive to a virtual machine"
  arg :vm, nil, :lookup => VIM::VirtualMachine
  opt :size, 'Size', :default => '10G'
  opt :controller, 'Virtual controller', :type => :string, :lookup => VIM::VirtualController
end

def add_disk vm, opts
  controller, unit_number = pick_controller vm, opts[:controller], [VIM::VirtualSCSIController, VIM::VirtualIDEController]
  id = "disk-#{controller.key}-#{unit_number}"
  filename = "#{File.dirname(vm.summary.config.vmPathName)}/#{id}.vmdk"
  _add_device vm, :create, VIM::VirtualDisk(
    :key => -1,
    :backing => VIM.VirtualDiskFlatVer2BackingInfo(
      :fileName => filename,
      :diskMode => :persistent,
      :thinProvisioned => true
    ),
    :capacityInKB => MetricNumber.parse(opts[:size]).to_i/1000,
    :controllerKey => controller.key,
    :unitNumber => unit_number
  )
end


opts :add_cdrom do
  summary "Add a cdrom drive"
  arg :vm, nil, :lookup => VIM::VirtualMachine
  opt :controller, 'Virtual controller', :type => :string, :lookup => VIM::VirtualIDEController
end

def add_cdrom vm, opts
  controller, unit_number = pick_controller vm, opts[:controller], [VIM::VirtualIDEController]
  id = "cdrom-#{controller.key}-#{unit_number}"
  _add_device vm, nil, VIM.VirtualCdrom(
    :controllerKey => controller.key,
    :key => -1,
    :unitNumber => unit_number,
    :backing => VIM.VirtualCdromAtapiBackingInfo(
      :deviceName => id,
      :useAutoDetect => false
    ),
    :connectable => VIM.VirtualDeviceConnectInfo(
      :allowGuestControl => true,
      :connected => true,
      :startConnected => true
    )
  )
end


opts :insert_cdrom do
  summary "Put a disc in a virtual CDROM drive"
  arg :dev, nil, :lookup => VIM::VirtualDevice
  arg :iso, "Path to the ISO image on a datastore", :lookup => VIM::Datastore::FakeDatastoreFile
end

def insert_cdrom dev, iso
  vm = dev.rvc_vm
  backing = VIM.VirtualCdromIsoBackingInfo(:fileName => iso.datastore_path)

  spec = {
    :deviceChange => [
      {
        :operation => :edit,
        :device => dev.class.new(
          :key => dev.key,
          :controllerKey => dev.controllerKey,
          :backing => backing)
      }
    ]
  }

  progress [vm.ReconfigVM_Task(:spec => spec)]
end


SCSI_CONTROLLER_TYPES = {
  'pvscsi' => VIM::ParaVirtualSCSIController,
  'buslogic' => VIM::VirtualBusLogicController,
  'lsilogic' => VIM::VirtualLsiLogicController,
  'lsilogic-sas' => VIM::VirtualLsiLogicSASController,
}

SCSI_BUS_NUMBERS = [0, 1, 2, 3]

opts :add_scsi_controller do
  summary "Add a virtual SCSI controller to a VM"
  arg :vm, nil, :lookup => VIM::VirtualMachine
  opt :type, SCSI_CONTROLLER_TYPES.keys*'/', :default => 'lsilogic' # TODO tab complete
  opt :sharing, VIM::VirtualSCSISharing.values*'/', :default => 'noSharing' # TODO tab complete
  opt :hot_add, "Enable hot-add/remove", :default => nil
end

def add_scsi_controller vm, opts
  klass = SCSI_CONTROLLER_TYPES[opts[:type]] or err "invalid SCSI controller type #{opts[:type].inspect}"
  err "invalid value for --sharing" unless VIM::VirtualSCSISharing.values.member? opts[:sharing]

  existing_devices, = vm.collect 'config.hardware.device'
  used_bus_numbers = existing_devices.grep(VIM::VirtualSCSIController).map(&:busNumber)
  bus_number = (SCSI_BUS_NUMBERS - used_bus_numbers).min
  err "unable to allocate a bus number, too many SCSI controllers" unless bus_number

  controller = klass.new(
    :key => -1,
    :busNumber => bus_number,
    :sharedBus => opts[:sharing],
    :hotAddRemove => opts[:hot_add]
  )

  _add_device vm, nil, controller
end


def _add_device vm, fileOp, dev
  spec = {
    :deviceChange => [
      { :operation => :add, :fileOperation => fileOp, :device => dev },
    ]
  }
  task = vm.ReconfigVM_Task(:spec => spec)
  result = progress([task])[task]
  if result == nil
    new_device = vm.collect('config.hardware.device')[0].grep(dev.class).last
    puts "Added device #{new_device.deviceInfo.label.inspect}"
  end
end

def change_devices_connectivity devs, connected
  if dev = devs.find { |dev| dev.connectable.nil? }
    err "#{dev.deviceInfo.label} is not connectable."
  end

  vm_devs = devs.group_by(&:rvc_vm)
  tasks = vm_devs.map do |vm,my_devs|
    device_changes = my_devs.map do |dev|
      {
        :operation => :edit,
        :device => dev.class.new(
          :key => dev.key,
          :connectable => {
            :allowGuestControl => dev.connectable.allowGuestControl,
            :connected => connected,
            :startConnected => connected
          }
        )
      }
    end
    spec = { :deviceChange => device_changes }
    vm.ReconfigVM_Task(:spec => spec)
  end

  progress tasks
end

def pick_controller vm, controller, controller_classes
  existing_devices, = vm.collect 'config.hardware.device'

  controller ||= existing_devices.find do |dev|
    controller_classes.any? { |klass| dev.is_a? klass } &&
      dev.device.length < 2
  end
  err "no suitable controller found" unless controller

  used_unit_numbers = existing_devices.select { |dev| dev.controllerKey == controller.key }.map(&:unitNumber)
  unit_number = (used_unit_numbers.max||-1) + 1

  [controller, unit_number]
end
