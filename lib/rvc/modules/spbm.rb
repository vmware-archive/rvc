# Copyright (c) 2013 VMware, Inc.  All Rights Reserved.
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

require 'rbvmomi/vim'
require 'rbvmomi/pbm'
require 'rvc/vim'

PBM = RbVmomi::PBM

class RbVmomi::VIM
  def pbm
    @pbm ||= PBM.connect self, :insecure => true
  end
  
  def pbm= x
    @pbm = nil
  end
end

RbVmomi::VIM::Datacenter
class RbVmomi::VIM::Datacenter
  def rvc_list_children_profiles
    {
      'storage' => RVC::FakeFolder.new(self, :rvc_children_storage),
    }
  end

  def rvc_children_storage
    {
      'vmprofiles' => RVC::FakeFolder.new(self, :rvc_children_profiles),
    }
  end
  
  def rvc_children_profiles
    conn = _connection
    _catch_spbm_resets(conn) do 
      pbm = conn.pbm
      pm = pbm.serviceContent.profileManager
      profileIds = pm.PbmQueryProfile(
        :resourceType => {:resourceType => "STORAGE"}, 
        :profileCategory => "REQUIREMENT"
      )
      if profileIds.length > 0
        profiles = pm.PbmRetrieveContent(:profileIds => profileIds)
      else
        profiles = []
      end
      
      Hash[profiles.map do |x|
        x.instance_variable_set(:@connection, pbm) 
        x.instance_variable_set(:@dc, self) 
        [x.name, x]
      end]
    end
  end
end

RbVmomi::PBM::PbmCapabilityInstance
class RbVmomi::PBM::PbmCapabilityInstance
  def name
    "#{self.id.namespace}.#{self.id.id}"
  end
end


RbVmomi::PBM::PbmCapabilityMetadata
class RbVmomi::PBM::PbmCapabilityMetadata
  def name
    "#{self.id.namespace}.#{self.id.id}"
  end
end

RbVmomi::VIM::VirtualDisk
class RbVmomi::VIM::VirtualDisk
  def rvc_display_info_vsan
    if self.backing.backingObjectId
      puts "VSAN objects:"
      backing = self.backing
      while backing
        puts "  #{backing.backingObjectId}"
        backing = backing.parent
      end
    end
  end
  
end

RbVmomi::VIM::Datastore
class RbVmomi::VIM::Datastore
  def to_pbmhub
    PBM::PbmPlacementPlacementHub(:hubType => "Datastore", :hubId => _ref)
  end
  
  def pbm_capability_profiles
    pbm_associated_profiles
  end
  
  def rvc_list_children_capabilitysets
    {
      'capabilitysets' => RVC::FakeFolder.new(self, :rvc_children_capabilitysets),
    }
  end

  def rvc_children_capabilitysets
    conn = _connection
    _catch_spbm_resets(conn) do 
      pbm = _connection.pbm
      profiles = pbm_capability_profiles
      Hash[profiles.map do |x|
        x.instance_variable_set(:@connection, pbm) 
        x.instance_variable_set(:@dc, self) 
        [x.name, x]
      end]
    end
  end
end

RbVmomi::VIM::VirtualMachine
class RbVmomi::VIM::VirtualMachine
  def rvc_list_children_vmprofiles
    {
      'vmprofiles' => RVC::FakeFolder.new(self, :rvc_children_vmprofiles),
    }
  end

  def rvc_children_vmprofiles
    conn = _connection
    _catch_spbm_resets(conn) do 
      pbm = _connection.pbm
      profiles = pbm_associated_profiles
      Hash[profiles.map do |x|
        x.instance_variable_set(:@connection, pbm) 
        x.instance_variable_set(:@dc, self) 
        [x.name, x]
      end]
    end
  end
end

RbVmomi::VIM::ManagedObject
class RbVmomi::VIM::ManagedObject
  def to_pbmobjref
    type = self.class.wsdl_name
    type = "%s%s" % [type[0].downcase, type[1..-1]] 
    PBM::PbmServerObjectRef(
      :objectType => type,
      :key => _ref,
      :serverUuid => _connection.serviceContent.about.instanceUuid
    )
  end

  def pbm_associated_profiles
    conn = _connection
    _catch_spbm_resets(conn) do 
      pbm = _connection.pbm
      pm = pbm.serviceContent.profileManager
      ids = pm.QueryAssociatedProfile(:entity => self.to_pbmobjref)
      pm.retrieveProfileContent(:profileIds => ids) 
    end
  end

  def _catch_spbm_resets(conn)
    begin
      yield
    rescue EOFError
      if conn
        conn.pbm = nil
      end
      raise "Connection to SPBM timed out, try again"
    end
  end
end

RbVmomi::VIM::VirtualMachine
class RbVmomi::VIM::VirtualMachine
  def disks_pbmobjref
    disks.map do |disk|
      PBM::PbmServerObjectRef(
        :objectType => "virtualDiskId",
        :key => "#{self._ref}:#{disk.key}",
        :serverUuid => _connection.serviceContent.about.instanceUuid
      )
    end
  end
  
  def all_pbmobjref
    [to_pbmobjref] + disks_pbmobjref
  end
end

RbVmomi::PBM::PbmPlacementSolver
class RbVmomi::PBM::PbmPlacementSolver
  def find_compatible_datastores datastores, profileIds
    if profileIds.length > 1
      raise Exception("Passing in more than one profile currently not supported")
    end
    dsMoMap = Hash[datastores.map{|x| [x._ref, x]}]
    results = self.Solve(
      :hubsToSearch => datastores.map{|x| x.to_pbmhub}, 
      :requirements => [
        {
          :subject => PBM.PbmPlacementPlacementSubject(
            :subjectType=>"VirtualMachine", 
            :subjectId=>"fake"
          ), 
          :requirement => [
            PBM::PbmPlacementCapabilityProfileRequirement(
              :requirementType => "type", 
              :mandatory => true, 
              :profileId => profileIds[0]
            )
          ],
        }
      ], 
      :partialSolution => false
    )
    compatibleDsList = results.map do |x| 
      dsMoMap[x.subjectAssignment[0].hub.hubId]
    end
  end
end

RbVmomi::PBM::PbmCapabilityProfile
class RbVmomi::PBM::PbmCapabilityProfile
  include InventoryObject
  
  def children
    {
      'datastores' => RVC::FakeFolder.new(self, :rvc_children_datastores),
      'vms' => RVC::FakeFolder.new(self, :rvc_children_vms),
    }
  end

  def rvc_children_vms
    pbm = @connection
    vim = @dc._connection
    pc = vim.propertyCollector
    
    vms = pm.QueryAssociatedEntity(
      :profile => self.profileId, 
      :entityType => 'virtualMachine'
    )
    vms = vms.map do |ref|
      VIM::VirtualMachine(vim, ref.key)
    end
    props = pc.collectMultiple(vms, 'name')
    Hash[props.map do |vm, vm_props|
      [vm_props['name'], vm]
    end]
  end
  
  def rvc_children_datastores
    pbm = @connection
    vim = @dc._connection
    pc = vim.propertyCollector
    _catch_spbm_resets(vim) do 
      solver = pbm.serviceContent.placementSolver
      datastores = solver.find_compatible_datastores @dc.datastore, [profileId]
      props = pc.collectMultiple(datastores, 'name')
      Hash[props.map do |ds, ds_props|
        [ds_props['name'], ds]
      end]
    end
  end
  
  def display_info
    super
    puts "Name: #{name}"
    puts "Description:"
    puts description
    puts "ProfileId: #{profileId.uniqueId}"
    puts "Type: #{resourceType.resourceType} - #{profileCategory}"
    puts "Rule-Sets:"
    constraints.subProfiles.each_with_index do |sub, i|
      puts "  Rule-Set ##{i + 1}:"
      sub.capability.each do |rule|
        instances = rule.constraint.map{|c| c.propertyInstance}.flatten
        if instances.length > 1
          raise "Can't deal with multiple constraints in single rule"
        end
        value = instances[0].value
        if value.is_a?(RbVmomi::PBM::PbmCapabilityRange)
          value = "#{value.min} - #{value.max}"
        end
        puts "    #{rule.name}: #{value}"
      end
    end
  end
end


opts :profile_delete do
  summary "Delete a VM Storage Profile"
  arg :profile, nil, :lookup => RbVmomi::PBM::PbmCapabilityProfile, :multi => true
end

def profile_delete profiles
  if profiles.length == 0
    return
  end
  _catch_spbm_resets(nil) do 
    pbm = profiles.first.instance_variable_get(:@connection)
    pm = pbm.serviceContent.profileManager
    pm.PbmDelete(:profileId => profiles.map{|x| x.profileId})
  end
end


opts :profile_apply do
  summary "Apply a VM Storage Profile. Pushed profile content to Storage system"
  arg :profile, nil, :lookup => RbVmomi::PBM::PbmCapabilityProfile, :multi => true
end

def profile_apply profiles
  if profiles.length == 0
    return
  end
  pbm = profiles.first.instance_variable_get(:@connection)
  dc = profiles.first.instance_variable_get(:@dc)
  vim = dc._connection
  _catch_spbm_resets(vim) do 
    pm = pbm.serviceContent.profileManager
    results = pm.applyProfile(:profiles => profiles.map{|x| x.profileId})
    tasks = results.map{|x| x.reconfigOutcome.map{|y| y.taskMoid}}.flatten
    tasks = tasks.map{|x| VIM::Task(vim, x)}
    progress(tasks)
  end
end


opts :profile_create do
  summary "Create a VM Storage Profile"
  arg :name, nil, :type => :string
  opt :description, "Description", :type => :string
  opt :rule, "Rule in format <provider>.<capability>=<value>", :type => :string, :multi => true
end

def profile_create profile_name, opts
  dc, = lookup '~'
  conn = dc._connection
  _catch_spbm_resets(conn) do 
    pbm = conn.pbm
    pm = pbm.serviceContent.profileManager
    
    rules = opts[:rule] || []
    resType = {:resourceType => "STORAGE"}
    
    # Need to support other vendors too
    cm = pm.PbmFetchCapabilityMetadata(
      :resourceType => resType, 
      :vendorUuid => "com.vmware.storage.vsan"
    )
    capabilities = cm.map{|x| x.capabilityMetadata}.flatten
    
    constraints = rules.map do |rule_str| 
      name, values_str = rule_str.split("=", 2)
      if !values_str
        err "Rule is malformed: #{rule_str}, should be <provider>.<capability>=<value>"
      end
      ns, id = name.split('.', 2)
      if !id
        err "Rule is malformed: #{rule_str}, should be <provider>.<capability>=<value>"
      end
      capability = capabilities.find{|x| x.name == name}
      if !capability
        err "Capability #{name} unknown"
      end
      type = capability.propertyMetadata[0].type
      values = values_str.split(',')
      if type.typeName == "XSD_INT"
        values = values.map{|x| RbVmomi::BasicTypes::Int.new(x.to_i)}
      end
      if type.typeName == "XSD_BOOLEAN"
        values = values.map{|x| (x =~ /(true|True|1|yes|Yes)/) != nil}
      end
      if type.is_a?(PBM::PbmCapabilityGenericTypeInfo) && type.genericTypeName == "VMW_RANGE"
        if values.length != 2
          err "#{name} is a range, need to specify 2 values"
        end
        value = PBM::PbmCapabilityTypesRange(:min => values[0], :max => values[1])
      elsif values.length == 1
        value = values.first
      else
        err "Value malformed: #{value_str}"
      end
      
      {
        :id => {
          :namespace => ns, 
          :id => id
        }, 
        :constraint => [{
          :propertyInstance => [{
            :id => id, 
            :value => value
          }]
        }]
      }
    end
    pm.PbmCreate(
      :createSpec => {
        :name => profile_name, 
        :description => opts[:description], 
        :resourceType => resType, 
        :constraints => PBM::PbmCapabilitySubProfileConstraints(
          :subProfiles => [
            PBM::PbmCapabilitySubProfile(
              :name => "Object", 
              :capability => constraints
            )
          ]
        )
      }
    )
  end
end

opts :device_change_storage_profile do
  summary "Change storage profile of a virtual disk"
  arg :device, nil, :lookup => VIM::VirtualDevice, :multi => true
  opt :profile, "Profile", :lookup => RbVmomi::PBM::PbmCapabilityProfile
end

def device_change_storage_profile devs, opts
  if !opts[:profile]
    err "Must specify a storage profile"
  end
  
  vm_devs = devs.group_by(&:rvc_vm)
  conn = vm_devs.keys.first._connection
  _catch_spbm_resets(conn) do 
    _run_with_rev(conn, "dev") do
      profile = nil
      if opts[:profile]
        profile = [VIM::VirtualMachineDefinedProfileSpec(
          :profileId => opts[:profile].profileId.uniqueId
        )]
      end
      tasks = vm_devs.map do |vm, my_devs|
        spec = {
          :deviceChange => my_devs.map do |dev|
            { 
              :operation => :edit, 
              :device => dev,
              :profile => profile,
            }
          end
        }
        vm.ReconfigVM_Task(:spec => spec)
      end
      progress(tasks)
    end
  end
end

opts :check_compliance do
  summary "Check compliance"
  arg :vm, nil, :lookup => VIM::VirtualMachine, :multi => true
end

def check_compliance vms
  dc, = lookup '~'
  conn = dc._connection
  _catch_spbm_resets(conn) do 
    pbm = conn.pbm
    pm = pbm.serviceContent.profileManager
    cm = pbm.serviceContent.complianceManager
  
    compliance = cm.PbmCheckCompliance(:entities => vms.map do |vm| 
      vm.all_pbmobjref
    end.flatten)
    profile_ids = Hash[compliance.map{|x| [x.entity.key, x.profile.uniqueId]}]
    compliances = Hash[compliance.map{|x| [x.entity.key, x.complianceStatus]}]
  
    profiles = nil
    begin
      profileIds = profile_ids.values.uniq.compact.map do |x| 
        PBM::PbmProfileId(:uniqueId => x)
      end
      if profileIds.length > 0
        profiles = pm.PbmRetrieveContent(
          :profileIds => profileIds
        )
      else
        profiles = []
      end
    rescue Exception => ex
      pp "#{ex.class}: #{ex.message}"
      pp profile_ids
      raise ex
    end
    profiles = Hash[profiles.map{|x| [x.profileId.uniqueId, x.name]}]
    profiles = Hash[profile_ids.map{|k,v| [k, profiles[v] || v]}]
    
    t = Terminal::Table.new()
    t << ['VM/Virtual Disk', 'Profile', 'Compliance']
    t.add_separator
    vms.each do |vm|
      t << [
        vm.name,
        profiles[vm._ref] || "unknown",
        compliances[vm._ref] || "unknown",
      ]
      vm.disks.each do |disk|
        id = "#{vm._ref}:#{disk.key}"
        t << [
          "  #{disk.deviceInfo.label}",
          profiles[id] || "unknown",
          compliances[id] || "unknown",
        ]
      end
    end
    puts t
    
    puts ""
    stats = Hash[compliances.values.group_by{|x| x}.map{|k,v| [k, v.length]}]
    stats.sort_by{|k,v| k}.each do |type, count|
      puts "Number of '#{type}' entities: #{count}"
    end
  end
end

opts :namespace_change_storage_profile do
  summary "Change storage profile of VM namespace"
  arg :vm, nil, :lookup => VIM::VirtualMachine, :multi => true
  opt :profile, "Profile", :lookup => RbVmomi::PBM::PbmCapabilityProfile
end

def namespace_change_storage_profile vms, opts
  if !opts[:profile]
    err "Must specify a storage profile"
  end
  
  conn = vms.first._connection 
  _catch_spbm_resets(conn) do 
    _run_with_rev(conn, "dev") do
      profile = nil
      if opts[:profile]
        profile = [VIM::VirtualMachineDefinedProfileSpec(
          :profileId => opts[:profile].profileId.uniqueId
        )]
      end
      tasks = vms.map do |vm|
        spec = {
          :vmProfile => profile,
        }
        vm.ReconfigVM_Task(:spec => spec)
      end
      progress(tasks)
    end
  end
end

opts :vm_change_storage_profile do
  summary "Change storage profile of VM namespace and its disks"
  arg :vm, nil, :lookup => VIM::VirtualMachine, :multi => true
  opt :profile, "Profile", :lookup => RbVmomi::PBM::PbmCapabilityProfile
end

def vm_change_storage_profile vms, opts
  if !opts[:profile]
    err "Must specify a storage profile"
  end

  conn = vms.first._connection  
  _catch_spbm_resets(conn) do 
    _run_with_rev(conn, "dev") do
      profile = nil
      if opts[:profile]
        profile = [VIM::VirtualMachineDefinedProfileSpec(
          :profileId => opts[:profile].profileId.uniqueId
        )]
      end
      tasks = vms.map do |vm|
        disks = vm.disks
        spec = {
          :vmProfile => profile,
          :deviceChange => disks.map do |dev|
            { 
              :operation => :edit, 
              :device => dev,
              :profile => profile,
            }
          end
        }
        vm.ReconfigVM_Task(:spec => spec)
      end
      progress(tasks)
    end
  end
end

opts :device_add_disk do
  summary "Add a hard drive to a virtual machine"
  arg :vm, nil, :lookup => VIM::VirtualMachine
  arg :path, "Filename on the datastore", :lookup_parent => VIM::Datastore::FakeDatastoreFolder, :required => false
  opt :size, 'Size', :default => '10G'
  opt :controller, 'Virtual controller', :type => :string, :lookup => VIM::VirtualController
  opt :file_op, 'File operation (create|reuse|replace)', :default => 'create'
  opt :profile, "Profile", :lookup => RbVmomi::PBM::PbmCapabilityProfile
end

def device_add_disk vm, path, opts
  controller, unit_number = pick_controller vm, opts[:controller], [VIM::VirtualSCSIController, VIM::VirtualIDEController]
  id = "disk-#{controller.key}-#{unit_number}"

  if path
    dir, file = *path
    filename = "#{dir.datastore_path}/#{file}"
  else
    filename = "#{File.dirname(vm.summary.config.vmPathName)}/#{id}.vmdk"
  end

  opts[:file_op] = nil if opts[:file_op] == 'reuse'

  conn = vm._connection  
  _run_with_rev(conn, "dev") do
    profile = nil
    if opts[:profile]
      profile = [VIM::VirtualMachineDefinedProfileSpec(
        :profileId => opts[:profile].profileId.uniqueId
      )]
    end
    spec = {
      :deviceChange => [
        { 
          :operation => :add, 
          :fileOperation => opts[:file_op], 
          :device => VIM::VirtualDisk(
            :key => -1,
            :backing => VIM.VirtualDiskFlatVer2BackingInfo(
              :fileName => filename,
              :diskMode => :persistent,
              :thinProvisioned => true
            ),
            :capacityInKB => MetricNumber.parse(opts[:size]).to_i/1000,
            :controllerKey => controller.key,
            :unitNumber => unit_number
          ),
          :profile => profile,
        },
      ]
    }
    task = vm.ReconfigVM_Task(:spec => spec)
    result = progress([task])[task]
    if result == nil
      new_device = vm.collect('config.hardware.device')[0].grep(VIM::VirtualDisk).last
      puts "Added device #{new_device.name}"
    end
  end
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


def _run_with_rev conn, rev
  old_rev = conn.rev
  begin
    conn.rev = rev
    yield
  ensure
    conn.rev = old_rev
  end
end

def _catch_spbm_resets(conn)
  begin
    yield
  rescue EOFError
    if conn
      conn.pbm = nil
    end
    err "Connection to SPBM timed out, try again"
  end
end
