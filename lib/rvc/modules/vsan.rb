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

require 'rvc/vim'
require 'json'
require 'time'
VIM::ClusterComputeResource

# Patch in some last minute additions to the API
db = VIM.loader.instance_variable_get(:@db)
db['HostVsanInternalSystem']['methods']["QuerySyncingVsanObjects"] = 
  {"params"=>
    [{"name"=>"uuids",
      "is-array"=>true,
      "is-optional"=>true,
      "version-id-ref"=>nil,
      "wsdl_type"=>"xsd:string"}],
   "result"=>
    {"is-array"=>false,
     "is-optional"=>false,
     "is-task"=>false,
     "version-id-ref"=>nil,
     "wsdl_type"=>"xsd:string"}}
db['HostVsanInternalSystem']['methods']["GetVsanObjExtAttrs"] = 
  {"params"=>
    [{"name"=>"uuids",
      "is-array"=>true,
      "is-optional"=>true,
      "version-id-ref"=>nil,
      "wsdl_type"=>"xsd:string"}],
   "result"=>
    {"is-array"=>false,
     "is-optional"=>false,
     "is-task"=>false,
     "version-id-ref"=>nil,
     "wsdl_type"=>"xsd:string"}}
db = nil

$vsanUseGzipApis = false

def is_uuid str
  str =~ /[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}/
end

opts :enable_vsan_on_cluster do
  summary "Enable VSAN on a cluster"
  arg :cluster, nil, :lookup => VIM::ClusterComputeResource
  opt :disable_storage_auto_claim, "Disable auto disk-claim", :type => :boolean
end

def enable_vsan_on_cluster cluster, opts
  conn = cluster._connection
  _run_with_rev(conn, "dev") do 
    spec = VIM::ClusterConfigSpecEx(
      :vsanConfig => {
        :enabled => true,
        :defaultConfig => {
          :autoClaimStorage => (!(opts[:disable_storage_auto_claim] || false)),
        }
      }
    )
    task = cluster.ReconfigureComputeResource_Task(:spec => spec, :modify => true)
    progress([task])
    childtasks = task.child_tasks
    if childtasks && childtasks.length > 0
      progress(childtasks)
    end
    childtasks = task.child_tasks
    if childtasks && childtasks.length > 0
      progress(childtasks)
    end
  end
end

opts :disable_vsan_on_cluster do
  summary "Disable VSAN on a cluster"
  arg :cluster, nil, :lookup => VIM::ClusterComputeResource
end

def disable_vsan_on_cluster cluster
  conn = cluster._connection
  _run_with_rev(conn, "dev") do 
    spec = VIM::ClusterConfigSpecEx(
      :vsanConfig => {
        :enabled => false,
      }
    )
    task = cluster.ReconfigureComputeResource_Task(:spec => spec, :modify => true)
    progress([task])
    childtasks = task.child_tasks
    if childtasks && childtasks.length > 0
      progress(childtasks)
    end
  end
end

VIM::HostSystem
class VIM::HostSystem
  def filtered_disks_for_vsan opts = {}
    vsan = opts[:vsanSystem] || self.configManager.vsanSystem
    stateFilter = opts[:state_filter] || /^eligible$/
    disks = vsan.QueryDisksForVsan()
    
    disks = disks.select do |disk|
      disk.state =~ stateFilter
    end
    
    if opts[:filter_ssd_by_model]
      disks = disks.select do |disk|
        model = [
          disk.disk.vendor,
          disk.disk.model
        ].compact.map{|x| x.strip}.join(" ")
        model_match = (model =~ opts[:filter_ssd_by_model])
        !disk.disk.ssd || model_match
      end
    end

    disks = disks.map{|x| x.disk}
    
    disks
  end
  
  def consume_disks_for_vsan opts = {}
    vsan = opts[:vsanSystem] || self.configManager.vsanSystem
    disks = filtered_disks_for_vsan(opts.merge(
      :state_filter => /^eligible$/,
      :vsanSystem => vsan
    ))
    if disks.length > 0
      vsan.AddDisks_Task(:disk => disks)
    end
  end
end

opts :host_consume_disks do
  summary "Consumes all eligible disks on a host"
  arg :host_or_cluster, nil, :lookup => [VIM::ComputeResource, VIM::HostSystem], :multi => true
  opt :filter_ssd_by_model, "Regex to apply as ssd model filter", :type => :string
end

def host_consume_disks hosts_or_clusters, opts
  conn = hosts_or_clusters.first._connection
  hosts = []
  hosts_or_clusters.each do |host_or_cluster|
    if host_or_cluster.is_a?(VIM::HostSystem)
      hosts << host_or_cluster
    else
      hosts += host_or_cluster.host
    end 
  end
  if opts[:filter_ssd_by_model]
    opts[:filter_ssd_by_model] = /#{opts[:filter_ssd_by_model]}/
  end
  tasks = []
  results = {}
  _run_with_rev(conn, "dev") do 
    tasks = hosts.map do |host|
      host.consume_disks_for_vsan(opts)
    end.compact
    if tasks.length > 0
      results = progress(tasks)
      pp results.values.flatten.map{|x| x.error}.compact
    else
      puts "No disks were consumed."
    end
    $claimResults = results
  end
  $disksCache = {}
end

opts :host_wipe_vsan_disks do
  summary "Wipes content of all VSAN disks on a host"
  arg :host, nil, :lookup => VIM::HostSystem, :multi => true
  opt :force, "Apply force", :type => :boolean
end

def host_wipe_vsan_disks hosts, opts
  conn = hosts.first._connection
  tasks = []
  _run_with_rev(conn, "dev") do
    tasks = hosts.map do |host|
      hostname = host.name
      disks = host.filtered_disks_for_vsan(:state_filter => /^inUse$/)
      if disks.length == 0
        next
      end
      if !opts[:force]
        # Don't actually wipe, but show a warning.
        disks.each do |disk|
          model = [
            disk.vendor,
            disk.model
          ].compact.map{|x| x.strip}.join(" ")
          puts "Would wipe disk #{disk.displayName} (#{model}, ssd = #{disk.ssd})"
        end
      end
      
      if opts[:force]
        #disks = disks.select{|x| x.ssd}
        #host.configManager.vsanSystem.RemoveDisk_Task(:disk => disks)
        # See PR 1077658
        vsan = host.configManager.vsanSystem
        vsan.RemoveDiskMapping_Task(:mapping => vsan.config.storageInfo.diskMapping)
      end
    end.compact
    if tasks.length > 0
      results = progress(tasks)
      pp results.values.flatten.map{|x| x.error}.compact
      $wipeResults = results
    end
  end
  if !opts[:force]
    puts ""
    puts "NO ACTION WAS TAKEN. Use --force to actually wipe."
    puts "CAUTION: Wiping disks means all user data will be destroyed!"
  end
  $disksCache = {}
end

opts :host_info do
  summary "Print VSAN info about a host"
  arg :host, nil, :lookup => VIM::HostSystem
end

def host_info host
  conn = host._connection
  _run_with_rev(conn, "dev") do 
    _host_info host
  end
end

opts :cluster_info do
  summary "Print VSAN info about a cluster"
  arg :cluster, nil, :lookup => VIM::ClusterComputeResource
end

def cluster_info cluster
  conn = cluster._connection
  pc = conn.propertyCollector
  
  hosts = cluster.host
  
  hosts_props = pc.collectMultiple(hosts, 'name', 'runtime.connectionState')
  connected_hosts = hosts_props.select do |k,v| 
    v['runtime.connectionState'] == 'connected'
  end.keys
  hosts = connected_hosts
      
  _run_with_rev(conn, "dev") do 
    hosts.each do |host|
      begin
        puts "Host: #{hosts_props[host]['name']}"
        _host_info host, "  "
      rescue Exception => ex
        puts "#{Time.now}: Got exception: #{ex.class}: #{ex.message}"
      end
      puts ""
    end
  end
end

opts :disks_info do
  summary "Print physical disk info about a host"
  arg :host, nil, :lookup => VIM::HostSystem, :multi => true
end

def disks_info hosts
  conn = hosts.first._connection
  pc = conn.propertyCollector
  _run_with_rev(conn, "dev") do 
    hosts.each do |host|
      if hosts.length > 0
        puts "Disks on host #{host.name}:"
      end

      dsList = host.datastore
      dsListProps = pc.collectMultiple(dsList, 'summary', 'name', 'info')
      vmfsDsList = dsListProps.select do |ds, props| 
        props['summary'].type == "VMFS"
      end.keys
      
      vsan = host.configManager.vsanSystem
      disks = vsan.QueryDisksForVsan()
      partitions = host.esxcli.storage.core.device.partition.list
      
      t = Terminal::Table.new()
      t << ['DisplayName', 'isSSD', 'Size', 'State']
      needSep = true
      disks.each do |disk|
        capacity = disk.disk.capacity
        size = capacity.block * capacity.blockSize
        sizeStr = "#{size / 1024**3} GB"
        state = disk.state
  #      if needSep
          t.add_separator
          needSep = false
  #      end
        if state != 'eligible' && disk.error
          state += " (#{disk.error.localizedMessage})"
          if disk.error.fault.is_a?(VIM::DiskHasPartitions)
            state += "\n"
            state += "\n"
            state += "Partition table:\n"
            
            partitions.select do |x|
              x.Device == disk.disk.canonicalName && x.Type != 0
            end.each do |x|
              partSize = x.Size.to_f / 1024**3
              types = {
                0xfb => 'vmfs',
                0xfc => 'coredump',
                0xfa => 'vsan',
                0x0 => 'unused',
                0x6 => 'vfat',
              }
              type = types[x.Type] || x.Type
              state += "#{x.Partition}: %.2f GB, type = #{type}" % partSize
              
              if type == "vmfs"
                vmfsStr = vmfsDsList.select do |vmfsDs|
                  props = dsListProps[vmfsDs]
                  props['info'].vmfs.extent.any? do |ext|
                    ext.diskName == x.Device && x.Partition == ext.partition
                  end
                end.map do |vmfsDs|
                  "'#{dsListProps[vmfsDs]['name']}'"
                end.join(", ")
                if vmfsStr
                  state += " (#{vmfsStr})"
                end
              end
              
              state += "\n"
            end
            needSep = true
          end
        end
        t << [
          [
            disk.disk.displayName,
            [
              disk.disk.vendor, 
              disk.disk.model
            ].compact.map{|x| x.strip}.join(" ")
          ].join("\n"),
          disk.disk.ssd ? "SSD" : "MD", 
          sizeStr, 
          state
        ]
      end
      puts t
      if hosts.length > 0
        puts ""
      end
    end  
  end
end
  
def _host_info host, prefix = ''
  configManager = host.configManager
  netSys = configManager.networkSystem
  vsan = configManager.vsanSystem
  config = vsan.config
  enabled = config.enabled
  line = lambda{|x| puts "#{prefix}#{x}" }
  line.call "VSAN enabled: %s" % (enabled ? "yes" : "no")
  if !enabled
    return
  end
  status = vsan.QueryHostStatus()
  line.call "Cluster info:"
  line.call "  Cluster role: #{status.nodeState.state}"
  line.call "  Cluster UUID: #{config.clusterInfo.uuid}"
  line.call "  Node UUID: #{config.clusterInfo.nodeUuid}"
  line.call "  Member UUIDs: #{status.memberUuid} (#{status.memberUuid.length})"
  line.call "Storage info:"
  line.call "  Auto claim: %s" % (config.storageInfo.autoClaimStorage ? "yes" : "no")
  line.call "  Disk Mappings:"
  if config.storageInfo.diskMapping.length == 0
    line.call "    None"
  end
  config.storageInfo.diskMapping.each do |mapping|
    capacity = mapping.ssd.capacity
    size = capacity.block * capacity.blockSize
    line.call  "    SSD: #{mapping.ssd.displayName} - #{size / 1024**3} GB"
    mapping.nonSsd.map do |md|
      capacity = md.capacity
      size = capacity.block * capacity.blockSize
      line.call "    MD: #{md.displayName} - #{size / 1024**3} GB"
    end
  end
  line.call  "NetworkInfo:"
  if config.networkInfo.port.length == 0
    line.call  "  Not configured"
  end
  vmknics, = netSys.collect 'networkConfig.vnic'
  config.networkInfo.port.each do |port|
    dev = port.device
    vmknic = vmknics.find{|x| x.device == dev}
    ip = "IP unknown"
    if vmknic
      ip = vmknic.spec.ip.ipAddress
    end
    line.call "  Adapter: #{dev} (#{ip})"
  end
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


opts :cluster_set_default_policy do
  summary "Set default policy on a cluster"
  arg :cluster, nil, :lookup => VIM::ClusterComputeResource
  arg :policy, nil, :type => :string
end

def cluster_set_default_policy cluster, policy
  hosts = cluster.host
  conn = cluster._connection
  pc = conn.propertyCollector
  _run_with_rev(conn, "dev") do 
    vsan, = hosts.first.collect 'configManager.vsanSystem'
    cluster_uuid, = vsan.collect 'config.clusterInfo.uuid'
    
    hosts.each do |host|
      policy_node = host.esxcli.vsan.policy
      ['cluster', 'vdisk', 'vmnamespace', 'vmswap'].each do |policy_class|
        policy_node.setdefault(
          :clusteruuid => cluster_uuid,
          :policy => policy,
          :policyclass => policy_class,
        )
      end
    end
  end
end

def _components_in_dom_config dom_config
  out = []
  if ['Component', 'Witness'].member?(dom_config['type'])
    out << dom_config
  else
    dom_config.select{|k,v| k =~ /child-\d+/}.each do |k, v|
      out += _components_in_dom_config v
    end
  end
  out
end

def _normalize_uuid uuid
  uuid = uuid.gsub("-", "")
  uuid = "%s-%s-%s-%s-%s" % [
    uuid[0..7], uuid[8..11], uuid[12..15], 
    uuid[16..19], uuid[20..31]
  ]
  uuid
end

def _print_dom_config_tree_int dom_config, dom_components_str, indent = 0
  pre = "  " * indent
  type = dom_config['type']
  children = dom_config.select{|k,v| k =~ /child-\d+/}.values
  if ['RAID_0', 'RAID_1', 'Concatenation'].member?(type)
    puts "#{pre}#{type}"
    children.each do |child|
      _print_dom_config_tree_int child, dom_components_str, indent + 1
    end
  elsif ['Configuration'].member?(type)
#    puts "#{pre}#{type}"
    children.each do |child|
      _print_dom_config_tree_int child, dom_components_str, indent + 1
    end
  elsif ['Witness', 'Component'].member?(type)
    comp_uuid = dom_config['componentUuid']
    info = dom_components_str[comp_uuid]
    line = "#{pre}#{type}: #{info[0]}"
    if info[2].length > 0
      puts "#{line} (#{info[1]},"
      puts "#{' ' * line.length}  #{info[2]})"
    else
      puts "#{line} (#{info[1]})"
    end
  end
end

def _print_dom_config_tree dom_obj_uuid, obj_infos, indent = 0, opts = {} 
  pre = "  " * indent
  dom_obj_infos = obj_infos['dom_objects'][dom_obj_uuid]
  if !dom_obj_infos
    puts "#{pre}Couldn't find info about DOM object '#{dom_obj_uuid}'"
    return
  end
  dom_obj = dom_obj_infos['config']
  policy = dom_obj_infos['policy']
   
  dom_components = _components_in_dom_config(dom_obj['content'])
  csn = nil
  begin
    csn = dom_obj['content']['attributes']['CSN']
  rescue
  end

  dom_components_str = Hash[dom_components.map do |dom_comp|
    attr = dom_comp['attributes']
    state = attr['componentState']
    comp_uuid = dom_comp['componentUuid']
    state_names = {
      '0' => 'FIRST',
      '1' => 'NONE',
      '2' => 'NEED_CONFIG',
      '3' => 'INITIALIZE',
      '4' => 'INITIALIZED',
      '5' => 'ACTIVE',
      '6' => 'ABSENT',
      '7' => 'STALE',
      '8' => 'RESYNCHING',
      '9' => 'DEGRADED',
      '10' => 'RECONFIGURING',
      '11' => 'CLEANUP',
      '12' => 'TRANSIENT',
      '13' => 'LAST',
    }
    state_name = state.to_s
    if state_names[state.to_s]
      state_name = "#{state_names[state.to_s]} (#{state})"
    end
    props = {
      'state' => state_name,
    }
    
    if state.to_s.to_i == 6 && attr['staleCsn']
      if attr['staleCsn'] != csn
        props['csn'] = "STALE (#{attr['staleCsn']}!=#{csn})" 
      end
    end
    
    comp_policy = {}
    ['readOPS', 'writeOPS'].select{|x| attr[x]}.each do |x|
      comp_policy[x] = attr[x]
    end
    if attr['readCacheReservation'] && attr['readCacheHitRate']
      comp_policy['rc size/hitrate'] = "%.2fGB/%d%%" % [
        attr['readCacheReservation'].to_f / 1024**3,
        attr['readCacheHitRate'],
      ]
    end
    if attr['bytesToSync'] 
      comp_policy['dataToSync'] = "%.2f GB" % [
        attr['bytesToSync'].to_f / 1024**3
      ]
    end
    
    lsom_object = obj_infos['lsom_objects'][comp_uuid]
    if lsom_object
      host = obj_infos['host_vsan_uuids'][lsom_object['owner']]
      if host
        hostName = obj_infos['host_props'][host]['name']
      else
        hostName = "unknown"
      end
      md_uuid = dom_comp['diskUuid']
      md = obj_infos['vsan_disk_uuids'][md_uuid]
      ssd_uuid = obj_infos['disk_objects'][md_uuid]['content']['ssdUuid']
      #pp ssd_uuid
      ssd = obj_infos['vsan_disk_uuids'][ssd_uuid]
      #pp ssd
      props.merge!({
        'host' => hostName,
        'md' => md ? md.DisplayName : "unknown",
        'ssd' => ssd ? ssd.DisplayName : "unknown",
      })
      if opts[:highlight_disk] && md_uuid == opts[:highlight_disk]
        props['md'] = "**#{props['md']}**"
      elsif opts[:highlight_disk] && ssd_uuid == opts[:highlight_disk]
        props['ssd'] = "**#{props['ssd']}**"
      end
    else
      props.merge!({
        'host' => "LSOM object not found"
      })
    end
    propsStr = props.map{|k,v| "#{k}: #{v}"}.join(", ")
    comp_policy_str = comp_policy.map{|k,v| "#{k}: #{v}"}.join(", ")
    [comp_uuid, [comp_uuid, propsStr, comp_policy_str]]
  end]
    
  if policy
    policy = policy.map{|k,v| "#{k} = #{v}"}.join(", ")
  else
    policy = "No POLICY entry found in CMMDS"
  end
  owner = obj_infos['host_vsan_uuids'][dom_obj['owner']]
  if owner
    owner = obj_infos['host_props'][owner]['name']
  else
    owner = "unknown"
  end
  
  puts "#{pre}DOM Object: #{dom_obj['uuid']} (owner: #{owner}, policy: #{policy})"
  if opts[:context]
    puts "#{pre}  Context: #{opts[:context]}"
  end
  _print_dom_config_tree_int dom_obj['content'], dom_components_str, indent
end

# hosts is a hash: host => hostname
def _vsan_host_disks_info hosts
  hosts.each do |k,v| 
    if !v
      hosts[k] = k.name
    end
  end
  
  conn = hosts.keys.first._connection
  vsanDiskUuids = {}
  $disksCache ||= {}
  if !hosts.keys.all?{|x| $disksCache[x]}
    lock = Mutex.new
    hosts.map do |host, hostname|
      Thread.new do 
        if !$disksCache[host]
          c1 = conn.spawn_additional_connection
          host2 = host.dup_on_conn(c1)
          $disksCache[host] = []
          lock.synchronize do 
            puts "#{Time.now}: Fetching VSAN disk info from #{hostname} (may take a moment) ..."
          end
          begin
            timeout(45) do 
              list = host2.esxcli.vsan.storage.list
              list.each{|x| x._set_property :host, host}
              $disksCache[host] = list
            end
          rescue Exception => ex
            lock.synchronize do 
              puts "#{Time.now}: Failed to gather from #{hostname}: #{ex.class}: #{ex.message}"
            end
          end
        end
      end
    end.each{|t| t.join}
    puts "#{Time.now}: Done fetching VSAN disk infos"
  end

  hosts.map do |host, hostname|
    disks = $disksCache[host] 
    disks.each do |disk|
      vsanDiskUuids[disk.VSANUUID] = disk
    end
  end
  
  vsanDiskUuids
end

def _vsan_cluster_disks_info cluster, opts = {}
  pc = cluster._connection.propertyCollector
  if cluster.is_a?(VIM::HostSystem)
    hosts = [cluster]
  else
    hosts = cluster.host
  end
  if opts[:hosts_props]
    hosts_props = opts[:hosts_props]
  else
    hosts_props = pc.collectMultiple(hosts, 
      'name',
      'runtime.connectionState',
      'configManager.vsanSystem',
      'configManager.vsanInternalSystem',
    )
  end
  hosts_props = hosts_props.select do |k,v| 
    v['runtime.connectionState'] == 'connected'
  end
  vsan_systems = hosts_props.map{|h,p| p['configManager.vsanSystem']}
  vsan_props = pc.collectMultiple(vsan_systems, 'config.clusterInfo')
  host_vsan_uuids = Hash[hosts_props.map do |host, props|
    vsan_system = props['configManager.vsanSystem']
    vsan_info = vsan_props[vsan_system]['config.clusterInfo']
    [vsan_info.nodeUuid, host]
  end]
  vsan_disk_uuids = {}
  vsan_disk_uuids.merge!(
    _vsan_host_disks_info(Hash[hosts_props.map{|h, p| [h, p['name']]}]) 
  )  
  
  [host_vsan_uuids, hosts_props, vsan_disk_uuids]
end

opts :object_info do
  summary "Fetch information about a VSAN object"
  arg :cluster, "Cluster on which to fetch the object info", :lookup => [VIM::HostSystem, VIM::ClusterComputeResource]
  arg :obj_uuid, nil, :type => :string, :multi => true
end

def object_info cluster, obj_uuids, opts = {}
  opts[:cluster] = cluster
  objs = _object_info obj_uuids, opts
  indent = 0
  obj_uuids.each do |obj_uuid|
    _print_dom_config_tree(obj_uuid, objs, indent)
    puts ""
  end
end

opts :disk_object_info do
  summary "Fetch information about all VSAN objects on a given physical disk"
  arg :cluster_or_host, "Cluster or host on which to fetch the object info", :lookup => VIM::ClusterComputeResource
  arg :disk_uuid, nil, :type => :string, :multi => true
end

def disk_object_info cluster_or_host, disk_uuids, opts = {}
  conn = cluster_or_host._connection
  pc = conn.propertyCollector
  
  if cluster_or_host.is_a?(VIM::ClusterComputeResource)
    cluster = cluster_or_host
    hosts = cluster.host
  else
    hosts = [cluster_or_host]
  end
  
  _run_with_rev(conn, "dev") do 
    # XXX: This doesn't yet work when no cluster is given
    host_vsan_uuids, hosts_props, vsan_disk_uuids = _vsan_cluster_disks_info(cluster)

    input_disk_uuids = []
    m_disk_uuids = []
    disk_uuids.each do |disk_uuid|
      disk = vsan_disk_uuids.find {|k,v| v.DisplayName == disk_uuid}
      if disk 
        input_disk_uuids <<  disk
        if disk[1].IsSSD
          disks = vsan_disk_uuids.find_all do |k,v|
            v.VSANDiskGroupName == disk_uuid unless v.IsSSD
          end 
          m_disk_uuids += disks
        else
          m_disk_uuids << disk
        end
      else
        input_disk_uuids << [disk_uuid]
        m_disk_uuids << [disk_uuid]
      end
    end
    input_disk_uuids.map! {|x| x[0]}
    m_disk_uuids.map! {|x| x[0]}

    connected_hosts = hosts_props.select do |k,v| 
      v['runtime.connectionState'] == 'connected'
    end.keys
    hosts = connected_hosts
    
    if hosts.length == 0
      err "Couldn't find any connected hosts"
    end
    
    dslist = hosts.first.datastore
    dslist_props = pc.collectMultiple(dslist, 'name', 'summary.type')
    vsandslist = dslist_props.select{|k, v| v['summary.type'] == 'vsan'}.keys
    vsands = vsandslist.first 
    if !vsands
      err "Couldn't find VSAN datastore"
    end
    vms = vsands.vm
    vms_props = pc.collectMultiple(vms, 
      'name', 'config.hardware.device', 
      'summary.config'
    )
    objects = {}
    vms.each do |vm|
      disks = vms_props[vm]['disks'] = 
        vms_props[vm]['config.hardware.device'].select{|x| x.is_a?(VIM::VirtualDisk)}
      namespaceUuid = vms_props[vm]['namespaceUuid'] = 
        vms_props[vm]['summary.config'].vmPathName.split("] ")[1].split("/")[0]

      objects[namespaceUuid] = [vm, :namespace]
      disks.each do |disk|
        backing = disk.backing
        while backing
          objects[backing.backingObjectId] = [vm, backing.fileName]
          backing = backing.parent
        end
      end
    end

    vsanIntSys = hosts_props[hosts.first]['configManager.vsanInternalSystem']
    json = vsanIntSys.QueryObjectsOnPhysicalVsanDisk(:disks => m_disk_uuids)
    if json == "BAD"
      err "Server rejected VSAN object-on-disk query"
    end
    result = nil
    begin
      result = JSON.load(json)
    rescue
      err "Server failed to query VSAN objects-on-disk: #{json}"
    end

    result.merge!({
      'host_vsan_uuids' => host_vsan_uuids,
      'host_props' => hosts_props,
      'vsan_disk_uuids' => vsan_disk_uuids,
    })

    input_disk_uuids.each do |disk_uuid|
      dom_obj_uuids = [] 
      disk_info = vsan_disk_uuids[disk_uuid]
      if disk_info
        name = "#{disk_info.DisplayName} (#{disk_uuid})"
        if disk_info.IsSSD
          m_disks = vsan_disk_uuids.find_all do 
            |k, v| v.VSANDiskGroupUUID == disk_uuid unless v.IsSSD
          end
          m_disks ? m_disks.map!{|x| x[0]} : disk_uuid
          m_disks.each {|m_disk| dom_obj_uuids += result['objects_on_disks'][m_disk]}
        else
          dom_obj_uuids = result['objects_on_disks'][disk_uuid]
        end
      else
        name = disk_uuid
      end
      puts "Physical disk #{name}:"
      indent = 1
      dom_obj_uuids.each do |obj_uuid|
        object = objects[obj_uuid]
        if object && object[1] == :namespace
          vm_name = vms_props[object[0]]['name']
          context = "Part of VM #{vm_name}: Namespace directory"
        elsif object
          vm_name = vms_props[object[0]]['name']
          context = "Part of VM #{vm_name}: Disk: #{object[1]}"
        else
          context = "Can't attribute object to any VM, may be swap?"
        end
        _print_dom_config_tree(
          obj_uuid, result, indent, 
          :highlight_disk => disk_uuid,
          :context => context
        )
      end
      puts ""
    end
  end
end


opts :cmmds_find do
  summary "CMMDS Find"
  arg :cluster_or_host, nil, :lookup => [VIM::ClusterComputeResource, VIM::HostSystem]
  opt :type, "CMMDS type, e.g. DOM_OBJECT, LSOM_OBJECT, POLICY, DISK etc.", :type => :string, :short => 't'
  opt :uuid, "UUID of the entry.", :type => :string, :short => 'u'
  opt :owner, "UUID of the owning node.", :type => :string, :short => 'o' 
end

def cmmds_find cluster_or_host, opts
  conn = cluster_or_host._connection
  pc = conn.propertyCollector
  host = cluster_or_host
  entries = []
  hostUuidMap = {}
  _run_with_rev(conn, "dev") do
    vsanIntSys = nil
    if cluster_or_host.is_a?(VIM::ClusterComputeResource)
      cluster = cluster_or_host
      hosts = cluster.host
    else
      hosts = [host]
    end
    
    hosts_props = pc.collectMultiple(hosts,
      'name', 
      'runtime.connectionState',
      'configManager.vsanSystem',
      'configManager.vsanInternalSystem'
    )
    connected_hosts = hosts_props.select do |k,v| 
      v['runtime.connectionState'] == 'connected'
    end.keys
    host = connected_hosts.first
    if !host
      err "Couldn't find any connected hosts"
    end
    vsanIntSys = hosts_props[host]['configManager.vsanInternalSystem']
    vsanSysList = Hash[hosts_props.map do |host, props| 
      [props['name'], props['configManager.vsanSystem']]
    end]
    clusterInfos = pc.collectMultiple(vsanSysList.values, 
                                      'config.clusterInfo')
    hostUuidMap = Hash[vsanSysList.map do |hostname, sys|
      [clusterInfos[sys]['config.clusterInfo'].nodeUuid, hostname] 
    end]
    entries = vsanIntSys.query_cmmds([{
      :owner => opts[:owner],
      :uuid => opts[:uuid],
      :type => opts[:type],
    }], :gzip => true)
  end

  t = Terminal::Table.new()
  t << ['#', 'Type', 'UUID', 'Owner', 'Health', 'Content']
  t.add_separator
  entries.each_with_index do |entry, i|
    t << [
      i + 1,
      entry['type'],
      entry['uuid'],
      hostUuidMap[entry['owner']] || entry['owner'],
      entry['health'],
      PP.pp(entry['content'], ''),
    ]
  end
  
  puts t
end

def _get_vm_obj_uuids vm, vmsProps
  obj_uuids = {}
  disks = vmsProps[vm]['disks'] = 
    vmsProps[vm]['config.hardware.device'].select{|x| x.is_a?(VIM::VirtualDisk)}
  pathName = vmsProps[vm]['summary.config'].vmPathName
  namespaceUuid = vmsProps[vm]['namespaceUuid'] = 
    pathName.split("] ")[1].split("/")[0]
  obj_uuids[namespaceUuid] = pathName
  disks.each do |disk|
    backing = disk.backing
    while backing
      obj_uuids[backing.backingObjectId] = backing.fileName
      backing = backing.parent
    end
  end
  obj_uuids
end

def convert_uuids uuids
  nUuids = {}
  uuids.each do |uuid|
    begin
      oUuid = uuid.split(' ').join()
      nUuids[oUuid[0..7] + '-' + oUuid[8..11] + '-' + 
             oUuid[12..20] + '-' + oUuid[21..-1]] = true
    rescue Exception => ex
      puts "Ignoring malformed uuid #{uuid}: #{ex.class}: #{ex.message}"
    end
  end
  
  return nUuids
end

# It is possible for the management stack (hostd and vc) to lose the handle of
# a VM which is powered on (has a running vmx instance). No further operations
# can be performed on the VM because the running vmx holds locks on the VM.
# This API is intended to find such VMs. We look for VMs who's power state
# is not poweredOn (poweredOff, unknown, etc) for which there is a running vmx
# instance on any host in the cluster.

def find_inconsistent_vms cluster_or_host
  if cluster_or_host.is_a?(VIM::ClusterComputeResource)
    hosts = cluster_or_host.host
  else
    hosts = [host]
  end

  # Find all non-poweredon vms.
  conn = hosts.first._connection
  pc = conn.propertyCollector
  vms = pc.collectMultiple(hosts, 'vm').values.map{|x| x['vm']}.flatten
  vmProps = pc.collectMultiple(vms, 'name', 'runtime.powerState',
                               'summary.config.uuid')
  notOnVMs = vmProps.select{|vm, p| p['runtime.powerState'] !=
                                    'poweredOn'}.keys
  
  # Get list of all running vms on all hosts in parallel.
  threads = []
  processList = {}
  hosts.each do |host|
    threads << Thread.new do
      begin
        processList[host] = host.esxcli.vm.process.list
      rescue Exception => ex
        puts "Error getting vm process list on #{host.name}: " \
             "#{ex.class}: #{ex.message}"
      end
    end
  end
  threads.each{|t| t.join}
  uuids = convert_uuids(processList.values.flatten.map{|x| x.UUID})

  inconsistentVMs = notOnVMs.select{|vm|
                                    uuids.has_key?(vmProps[vm]['summary.config.uuid'])}
  if not inconsistentVMs.empty?
    puts "Found VMs for which VC/hostd/vmx are out of sync:"
    inconsistentVMs.each do |vm|
      puts "#{vmProps[vm]['name']}"
    end
  else
    puts "Did not find VMs for which VC/hostd/vmx are out of sync"
  end
  
  return inconsistentVMs
end

def fix_inconsistent_vms vms
  begin
    tasks = []    
    vms.each do |vm|
      begin
        path = vm.summary.config.vmPathName
        rp = vm.resourcePool
        folder = vm.parent
        name = vm.name
        host = vm.summary.runtime.host
        puts("Unregistering VM #{name}")
        vm.UnregisterVM()
        puts("Registering VM #{name}")
        tasks << folder.RegisterVM_Task(:path => path,
                                        :name => name,
                                        :asTemplate => false,
                                        :pool => rp,
                                        :host => host)
      rescue Exception => ex
        puts "Skipping VM #{name} due to exception: " \
             "#{ex.class}: #{ex.message}"
      end
    end
    progress(tasks)
  end
end

opts :fix_renamed_vms do
   summary "This command can be used to rename some VMs which get renamed " \
           "by the VC in case of storage inaccessibility. It is "           \
           "possible for some VMs to get renamed to vmx file path. "        \
           "eg. \"/vmfs/volumes/vsanDatastore/foo/foo.vmx\". This command " \
           "will rename this VM to \"foo\". This is the best we can do. "   \
           "This VM may have been named something else but we have no way " \
           "to know. In this best effort command, we simply rename it to "  \
           "the name of its config file (without the full path and .vmx "   \
           "extension ofcourse!)."
   arg :vms, nil, :lookup => VIM::VirtualMachine, :multi => true
end

def fix_renamed_vms vms
   begin
      conn = vms.first._connection
      pc = conn.propertyCollector
      vmProps = pc.collectMultiple(vms, 'name', 'summary.config.vmPathName')

      rename = {}
      puts "Continuing this command will rename the following VMs:"
      begin
         vmProps.each do |k,v|
            name = v['name']
            cfgPath = v['summary.config.vmPathName']
            if /.*vmfs.*volumes.*/.match(name)
               m = /.+\/(.+)\.vmx/.match(cfgPath)
               if name != m[1]
                  # Save it in a hash so we don't have to do it again if
                  # user choses Y.
                  rename[k] = m[1]
                  puts "#{name} -> #{m[1]}"
               end
            end
         end
      rescue Exception => ex
         # Swallow the exception. No need to stop other vms.
         puts "Skipping VM due to exception: #{ex.class}: #{ex.message}"
      end

      if rename.length == 0
         puts "Nothing to do"
         return
      end

      puts "Do you want to continue [y/N]?"
      opt = $stdin.gets.chomp
      if opt == 'y' || opt == 'Y'
         puts "Renaming..."
         tasks = rename.keys.map do |vm|
            vm.Rename_Task(:newName => rename[vm])
         end
         progress(tasks)
      end
   end
end

opts :vm_object_info do
  summary "Fetch VSAN object information about a VM"
  arg :vms, nil, :lookup => VIM::VirtualMachine, :multi => true
  opt :cluster, "Cluster on which to fetch the object info", :lookup => VIM::ClusterComputeResource
  opt :perspective_from_host, "Host to query object info from", :lookup => VIM::HostSystem
end

def vm_object_info vms, opts
  begin
  conn = vms.first._connection
  pc = conn.propertyCollector
  firstVm = vms.first
  host = firstVm.runtime.host
  if !host
    err "VM #{firstVm.name} doesn't have an assigned host (yet?)"
  end
  opts[:cluster] ||= host.parent
  _run_with_rev(conn, "dev") do 
    vmsProps = pc.collectMultiple(vms, 
      'name', 'config.hardware.device', 'summary.config',
      'runtime.host',
    )
    obj_uuids = []
    objToHostMap = {}
    vms.each do |vm|
      vm_obj_uuids = _get_vm_obj_uuids(vm, vmsProps).keys
      vm_obj_uuids.each{|x| objToHostMap[x] = vmsProps[vm]['runtime.host']}
      obj_uuids += vm_obj_uuids
    end
    opts[:objToHostMap] = objToHostMap

    objs = _object_info(obj_uuids, opts)
    hosts_props = objs['host_props']
    
    vms.each do |vm| 
      vmProps = vmsProps[vm]
      disks = vmProps['disks']
      puts "VM #{vmProps['name']}:"
      if objs['has_partitions']
        vmHost = vmProps['runtime.host']
        puts "  VM registered on host: #{hosts_props[vmHost]['name']}"
      end

      indent = 1
      pre = "  " * indent
      puts "#{pre}Namespace directory"
      obj_uuid = vmsProps[vm]['namespaceUuid']
      if objs['has_partitions'] && objs['obj_uuid_from_host'][obj_uuid]
        objHost = objs['obj_uuid_from_host'][obj_uuid]
        puts "#{pre}  Shown from perspective of host #{hosts_props[objHost]['name']}"
      end
      _print_dom_config_tree(obj_uuid, objs, indent + 1)
      
      disks.each do |disk|
        indent = 1
        backing = disk.backing
        while backing
          pre = "  " * indent
          puts "#{pre}Disk backing: #{backing.fileName}"
          obj_uuid = backing.backingObjectId
          if objs['has_partitions'] && objs['obj_uuid_from_host'][obj_uuid]
            objHost = objs['obj_uuid_from_host'][obj_uuid]
            puts "#{pre}  Shown from perspective of host #{hosts_props[objHost]['name']}"
          end
          _print_dom_config_tree(obj_uuid, objs, indent + 1)

          backing = backing.parent
          indent += 1
        end
      end
    end
  end
  rescue Exception => ex
    puts ex.message
    puts ex.backtrace
    raise
  end
end

def _object_info obj_uuids, opts
  if !opts[:cluster]
    err "Must specify a VSAN Cluster"
  end
  host = opts[:host]
  if opts[:cluster].is_a?(VIM::HostSystem)
    host = opts[:cluster]
  end
  # XXX: Verify VSAN is enabled on the cluster
  if host
    hosts = [host]
    conn = host._connection
  else
    hosts = opts[:cluster].host
    conn = opts[:cluster]._connection
  end
    
  _run_with_rev(conn, "dev") do 
    pc = conn.propertyCollector
    
    hosts_props = pc.collectMultiple(hosts, 
      'name', 'runtime.connectionState',
      'configManager.vsanSystem',
      'configManager.vsanInternalSystem'
    )
    connected_hosts = hosts_props.select do |k,v| 
      v['runtime.connectionState'] == 'connected'
    end.keys
    hosts = connected_hosts
    if hosts.length == 0
      err "Couldn't find any connected hosts"
    end
    
    if opts[:perspective_from_host]
      if !connected_hosts.member?(opts[:perspective_from_host])
        err "Perspective-Host not connected, or not in considered group of hosts"
      end
    end
    
    # Detect partitions:
    # We need to ask every host which other hosts it believes to share a 
    # VSAN cluster (partition) with. This is a call down to ESX, so we spawn
    # one connection and one thread per host to parallelize. We detect
    # partitions by grouping VMs based on quoting the same cluster members.
    hosts_props.map do |host, props|
      if !connected_hosts.member?(host)
        next
      end
      Thread.new do 
        begin
          vsanSys = props['configManager.vsanSystem']
          c1 = conn.spawn_additional_connection
          vsanSys  = vsanSys.dup_on_conn(c1)
          res = vsanSys.QueryHostStatus()
          hosts_props[host]['vsanCluster'] = res
        rescue Exception => ex
          puts "Failed to gather host status from #{props['name']}: #{ex.class}: #{ex.message}"
        end
      end
    end.compact.each{|t| t.join}
    
    partitions = hosts_props.select do |h, p|
      connected_hosts.member?(h)
    end.group_by{|h, p| p['vsanCluster'].memberUuid}
    partition_exists = (partitions.length > 1)
    if partition_exists
      puts "#{Time.now}: WARNING: VSAN Cluster network partition detected."
      puts "#{Time.now}: The individual partitions of the cluster will have "
      puts "#{Time.now}: different views on object/component availablity. An "
      puts "#{Time.now}: attempt is made to show VM object accessibility from the "
      puts "#{Time.now}: perspective of the host on which a VM is registered. "
      puts "#{Time.now}: Please fix the network partition as soon as possible "
      puts "#{Time.now}: as it will seriously impact the availability of your "
      puts "#{Time.now}: VMs in your VSAN cluster. Check vsan.cluster_info for"
      puts "#{Time.now}: more details."
      puts "#{Time.now}: "
      puts "#{Time.now}: The following partitions were detected:"
      i = 1
      partitions.values.map do |part| 
        part_hosts = part.map{|x| hosts_props[x[0]]}.compact.map{|x| x['name']}
        puts "#{Time.now}: #{i}) #{part_hosts.join(", ")}"
        i += 1
      end
      puts ""
      if opts[:perspective_from_host]
        name = hosts_props[opts[:perspective_from_host]]['name']
        puts "Showing data from perspective of host #{name} as requested"
        puts ""
      end
    end

    host_vsan_uuids, host_props, vsan_disk_uuids = _vsan_cluster_disks_info(
      opts[:cluster],
      :hosts_props => hosts_props
    )
    extra_info = {
      'host_vsan_uuids' => host_vsan_uuids,
      'host_props' => host_props,
      'vsan_disk_uuids' => vsan_disk_uuids,
    }

    obj_uuids = obj_uuids.compact.map{|x| _normalize_uuid(x)}
    obj_uuids = obj_uuids.select{|x| is_uuid(x)}

    objs = {'obj_uuid_from_host' => {}}
    objs['has_partitions'] = partition_exists
    
    # Dealing with partitions:
    # In the non-partitioned case we can just select any host and ask it
    # for the object info, given that CMMDS is (eventual) consistent
    # across the cluster. But during a network partition it is most logical
    # to ask the host on which a VM is registered about what it thinks about
    # the objects in question. So in case of a network partition we fall
    # back to a slower code path that asks each host individually about 
    # the objects it (hopefully) knows best about.
    # Note: Upon power on DRS will pick a host to power the VM on. That other
    # host may not be in the same partition and DRS doesn't know about it,
    # so although we tried to show the object from the "right" hosts perspective
    # it may still not be the right host when debugging a power on failure.
    if opts[:objToHostMap] && partition_exists && !opts[:perspective_from_host]
      obj_uuids_groups = obj_uuids.group_by{|x| opts[:objToHostMap][x]}
      obj_uuids_groups.each do |host, group|
        vsanIntSys = hosts_props[host]['configManager.vsanInternalSystem']
        group_objs = vsanIntSys.query_vsan_objects(:uuids => group)
        
        # Here we are merging and overriding potentially conflicting
        # information about LSOM_OBJECT and DISK entries. No smarts are
        # applied, as I am not aware of issues arising from those 
        # possible inconsistencies.
        group_objs.each do |k,v|
          objs[k] ||= {}
          objs[k].merge!(v)
        end
        group.each do |uuid|
          objs['obj_uuid_from_host'][uuid] = host
        end
      end
    else
      if opts[:perspective_from_host]
        host = opts[:perspective_from_host]
      else
        host = hosts.first
      end
      vsanIntSys = hosts_props[host]['configManager.vsanInternalSystem']
      objs = vsanIntSys.query_vsan_objects(:uuids => obj_uuids)
    end

    objs.merge!(extra_info)
    objs
  end
end


def _fetch_disk_stats obj, metrics, instances, opts = {}
  conn = obj._connection
  pm = conn.serviceContent.perfManager

  metrics.each do |x|
    err "no such metric #{x}" unless pm.perfcounter_hash.member? x
  end

  interval = pm.provider_summary(obj).refreshRate
  start_time = nil
  if interval == -1
    # Object does not support real time stats
    interval = 300
    start_time = Time.now - 300 * 5
  end
  stat_opts = {
    :interval => interval,
    :startTime => start_time,
    :instance => instances,
    :multi_instance => true,
  }
  stat_opts[:max_samples] = opts[:samples] if opts[:samples]
  res = pm.retrieve_stats [obj], metrics, stat_opts
  
  out = {}
  if res && res[obj]
    res[obj][:metrics].each do |key, values|
      metric, device = key
      out[device] ||= {}
      out[device][metric] = values
    end
  end
  out
end

opts :disks_stats do
  summary "Show stats on all disks in VSAN"
  arg :hosts_and_clusters, nil, :lookup => [VIM::HostSystem, VIM::ClusterComputeResource], :multi => true
  opt :compute_number_of_components, "Deprecated", :type => :boolean
  opt :show_iops, "Show deprecated fields", :type => :boolean 
end

def disks_stats hosts_and_clusters, opts = {}
  opts[:compute_number_of_components] = true
  conn = hosts_and_clusters.first._connection
  hosts = hosts_and_clusters.select{|x| x.is_a?(VIM::HostSystem)}
  clusters = hosts_and_clusters.select{|x| x.is_a?(VIM::ClusterComputeResource)}
  pc = conn.propertyCollector
  cluster_hosts = pc.collectMultiple(clusters, 'host')
  cluster_hosts.each do |cluster, props|
    hosts += props['host']
  end
  hosts = hosts.uniq
  _run_with_rev(conn, "dev") do
    hosts_props = pc.collectMultiple(hosts, 
      'name', 
      'runtime.connectionState',
      'configManager.vsanSystem', 
      'configManager.vsanInternalSystem'
    )
    
    hosts = hosts_props.select do |k,v| 
      v['runtime.connectionState'] == 'connected'
    end.keys
    if hosts.length == 0
      err "Couldn't find any connected hosts"
    end
    
    hosts_vsansys = Hash[hosts_props.map{|k,v| [v['configManager.vsanSystem'], k]}] 
    node_uuids = pc.collectMultiple(hosts_vsansys.keys, 'config.clusterInfo.nodeUuid')
    node_uuids = Hash[node_uuids.map do |k, v| 
      [v['config.clusterInfo.nodeUuid'], hosts_vsansys[k]]
    end]

    lock = Mutex.new 
    disks = {}
    vsanIntSys = hosts_props[hosts.first]['configManager.vsanInternalSystem']
    disks = vsanIntSys.QueryPhysicalVsanDisks(:props => [
      'lsom_objects_count',
      'uuid',
      'isSsd',
      'capacity',
      'capacityUsed',
      'capacityReserved',
      'iops',
      'iopsReserved',
      'disk_health',
    ])
    if disks == "BAD"
      err "Server failed to gather VSAN disk info"
    end
    begin
      disks = JSON.load(disks)
    rescue
      err "Server didn't provide VSAN disk info: #{disks}"
    end
    #pp disks

    vsan_disks_info = {}
    vsan_disks_info.merge!(
      _vsan_host_disks_info(Hash[hosts.map{|h| [h, hosts_props[h]['name']]}]) 
    )  
    disks.each do |k, v| 
      v['esxcli'] = vsan_disks_info[v['uuid']]
      if v['esxcli']
        v['host'] = v['esxcli']._get_property :host
      end
    end
    
    #pp vsan_disks_info
    #pp disks.values.map{|x| [x['host'], x['esxcli']]}
    #pp disks.values.group_by{|x| x['host']}.keys
  
    disks = disks.values.sort_by do |x| 
      host_props = hosts_props[x['host']]
      host_props ? host_props['name'] : ''
    end

    # Stats are now better handled by observer
    # disks.group_by{|x| x['host']}.each do |host, host_disks|
      # next if !host
      # devices = host_disks.map{|x| x['esxcli'].Device}
      # metrics = [
        # 'disk.numberReadAveraged', 'disk.numberWriteAveraged',
        # 'disk.deviceLatency', 'disk.maxTotalLatency',
        # 'disk.queueLatency', 'disk.kernelLatency'
      # ]
      # stats = _fetch_disk_stats host, metrics, devices
      # disks.each do |v|
        # if v['esxcli'] && stats[v['esxcli'].Device]
          # v['stats'] = stats[v['esxcli'].Device]
        # else
          # v['stats'] ||= {}
          # metrics.each{|m| v['stats'][m] ||= [-1] }
        # end
      # end
    # end
    
    t = Terminal::Table.new()
    if opts[:show_iops]
      t << [nil,           nil,     nil,    'Num', 'Capacity', nil, nil,        'Iops', nil,        nil,    ]
      t << ['DisplayName', 'Host', 'isSSD', 'Comp', 'Total', 'Used', 'Reserved', 'Total', 'Reserved', ]
    else
      t << [nil,           nil,     nil,    'Num',  'Capacity', nil,    nil,        'Status']
      t << ['DisplayName', 'Host', 'isSSD', 'Comp', 'Total',    'Used', 'Reserved', 'Health']
    end
    t.add_separator
    # XXX: Would be nice to show displayName and host
    
    groups = disks.group_by{|x| x['esxcli'] ? x['esxcli'].VSANDiskGroupUUID : nil}
    
    groups.each do |group, disks|
      disks.sort_by{|x| -x['isSsd']}.each do |x|
        info = x['esxcli']
        host_props = hosts_props[x['host']]
        cols = [
          info ? info.DisplayName : 'N/A',
          host_props ? host_props['name'] : 'N/A',
          #x['uuid'],
          (x['isSsd'] == 1) ? 'SSD' : 'MD',
          x['lsom_objects_count'] || 'N/A',
          "%.2f GB" % [x['capacity'].to_f / 1024**3],
          "%.0f %%" % [x['capacityUsed'].to_f * 100 / x['capacity'].to_f],
          "%.0f %%" % [x['capacityReserved'].to_f * 100 / x['capacity'].to_f],
        ]
        
        if opts[:show_iops]
          cols += [
            "%d" % [x['iops']],
            "%.0f %%" % [ x['iopsReserved'].to_f * 100 / x['iops'].to_f],
          ]
        end
        
        # cols += [
          # "%dr/%dw" % [x['stats']['disk.numberReadAveraged'].first,
                       # x['stats']['disk.numberWriteAveraged'].first],
          # "%dd/%dq/%dk" % [x['stats']['disk.deviceLatency'].first,
                           # x['stats']['disk.queueLatency'].first,
                           # x['stats']['disk.kernelLatency'].first,],
        # ]
        
        health = "N/A"
        if x['disk_health'] && x['disk_health']['healthFlags']
          flags = x['disk_health']['healthFlags']
          health = []
          {
            4 => "FAILED",
            5 => "OFFLINE",
            6 => "DECOMMISSIONED",
          }.each do |k, v|
            if flags & (1 << k) != 0
              health << v
            end
          end
          if health.length == 0
            health = "OK"
          else
            health = health.join(", ")
          end
          
        end
        cols += [
          health 
        ]

        t << cols
      end
      if group != groups.keys.last
        t.add_separator
      end
    end
    
    puts t
  end
end


opts :whatif_host_failures do
  summary "Simulates how host failures impact VSAN resource usage"
  banner <<-EOS

The command shows current VSAN disk usage, but also simulates how 
disk usage would evolve under a host failure. Concretely the simulation 
assumes that all objects would be brought back to full policy 
compliance by bringing up new mirrors of existing data. 
The command makes some simplifying assumptions about disk space 
balance in the cluster. It is mostly intended to do a rough estimate 
if a host failure would drive the cluster to being close to full.

EOS
  arg :hosts_and_clusters, nil, :lookup => [VIM::HostSystem, VIM::ClusterComputeResource], :multi => true
  opt :num_host_failures_to_simulate, "Number of host failures to simulate", :default => 1
  opt :show_current_usage_per_host, "Show current resources used per host"
end

def whatif_host_failures hosts_and_clusters, opts = {}
  opts[:compute_number_of_components] = true
  conn = hosts_and_clusters.first._connection
  hosts = hosts_and_clusters.select{|x| x.is_a?(VIM::HostSystem)}
  clusters = hosts_and_clusters.select{|x| x.is_a?(VIM::ClusterComputeResource)}
  pc = conn.propertyCollector
  cluster_hosts = pc.collectMultiple(clusters, 'host')
  cluster_hosts.each do |cluster, props|
    hosts += props['host']
  end
  hosts = hosts.uniq
  
  if opts[:num_host_failures_to_simulate] != 1
    err "Only simulation of 1 host failure has been implemented"
  end
  
  _run_with_rev(conn, "dev") do
    hosts_props = pc.collectMultiple(hosts, 
      'name', 
      'runtime.connectionState',
      'configManager.vsanSystem', 
      'configManager.vsanInternalSystem'
    )
    
    hosts = hosts_props.select do |k,v| 
      v['runtime.connectionState'] == 'connected'
    end.keys
    if hosts.length == 0
      err "Couldn't find any connected hosts"
    end
    
    hosts_vsansys = Hash[hosts_props.map{|k,v| [v['configManager.vsanSystem'], k]}] 
    node_uuids = pc.collectMultiple(hosts_vsansys.keys, 'config.clusterInfo.nodeUuid')
    node_uuids = Hash[node_uuids.map do |k, v| 
      [v['config.clusterInfo.nodeUuid'], hosts_vsansys[k]]
    end]

    lock = Mutex.new 
    disks = {}
    vsanIntSys = hosts_props[hosts.first]['configManager.vsanInternalSystem']
    disks = vsanIntSys.QueryPhysicalVsanDisks(:props => [
      'lsom_objects_count',
      'uuid',
      'isSsd',
      'capacity',
      'capacityUsed',
      'capacityReserved',
      'iops',
      'iopsReserved',
      'owner',
    ])
    if disks == "BAD"
      err "Server failed to gather VSAN disk info"
    end
    begin
      disks = JSON.load(disks)
    rescue
      err "Server didn't provide VSAN disk info: #{objs}"
    end
    
    # XXX: Do this in threads
    hosts.map do |host|
      Thread.new do 
        c1 = conn.spawn_additional_connection
        props = hosts_props[host]
        vsanIntSys2 = props['configManager.vsanInternalSystem']
        vsanIntSys3 = vsanIntSys2.dup_on_conn(c1)
        res = vsanIntSys3.query_vsan_statistics(:labels => ['lsom-node'])
        hosts_props[host]['lsom.node'] = res['lsom.node']
      end
    end.each{|t| t.join}
    
    hosts_disks = Hash[disks.values.group_by{|x| x['owner']}.map do |owner, hostDisks|
      props = {}
      hdds = hostDisks.select{|disk| disk['isSsd'] == 0}
      ssds = hostDisks.select{|disk| disk['isSsd'] == 1}
      hdds.each do |disk|
        [
          'capacityUsed', 'capacityReserved', 
          'capacity', 'lsom_objects_count'
        ].each do |x|
          props[x] ||= 0
          props[x] += disk[x]
        end
      end
      ssds.each do |disk|
        [
          'capacityReserved', 'capacity', 
        ].each do |x|
          props["ssd_#{x}"] ||= 0
          props["ssd_#{x}"] += disk[x]
        end
      end
      h = node_uuids[owner]
      props['host'] = h
      props['hostname'] = h ? hosts_props[h]['name'] : owner
      props['numHDDs'] = hdds.length
      props['maxComponents'] = 3000
      if hosts_props[h]['lsom.node']
        props['maxComponents'] = hosts_props[h]['lsom.node']['numMaxComponents']
      end
      [owner, props]
    end]
    
    sorted_hosts = hosts_disks.values.sort_by{|x| -x['capacityUsed']}
    
    if opts[:show_current_usage_per_host]
      puts "Current utilization of hosts:"
      t = Terminal::Table.new()
      t << [nil,    nil,       'HDD Capacity', nil,    nil,    'Components', 'SSD Capacity']
      t << ['Host', 'NumHDDs', 'Total',    'Used', 'Reserved', 'Used',       'Reserved']
      t.add_separator
      
      hosts_disks.each do |owner, x|
        cols = [
          x['hostname'],
          x['numHDDs'],
          "%.2f GB" % [x['capacity'].to_f / 1024**3],
          "%.0f %%" % [x['capacityUsed'].to_f * 100 / x['capacity'].to_f],
          "%.0f %%" % [x['capacityReserved'].to_f * 100 / x['capacity'].to_f],
          "%4u/%u (%.0f %%)" % [
            x['lsom_objects_count'], 
            x['maxComponents'], 
            x['lsom_objects_count'].to_f * 100 / x['maxComponents'].to_f
          ],
          "%.0f %%" % [x['ssd_capacityReserved'].to_f * 100 / x['ssd_capacity'].to_f],
        ]
        t << cols
      end
      puts t
      puts ""
    end

    puts "Simulating #{opts[:num_host_failures_to_simulate]} host failures:"
    puts ""
    worst_host = sorted_hosts[0]

    if sorted_hosts.length < 3
      puts "Cluster unable to regain full policy compliance after host failure, "
      puts "not enough hosts remaining."
      return
    end

    t = Terminal::Table.new()
    t << ["Resource", "Usage right now", "Usage after failure/re-protection"]
    t.add_separator
    capacityRow = ["HDD capacity"]

    # Capacity before failure
    used = sorted_hosts.map{|x| x['capacityUsed']}.sum
    total = sorted_hosts.map{|x| x['capacity']}.sum
    free = total - used
    usedPctOriginal = 100.0 - (free.to_f * 100 / total.to_f)
    capacityRow << "%3.0f%% used (%.2f GB free)" % [
      usedPctOriginal,
      free.to_f / 1024**3,
    ]
    
    # Capacity after rebuild
    used = sorted_hosts[1..-1].map{|x| x['capacityUsed']}.sum
    total = sorted_hosts[1..-1].map{|x| x['capacity']}.sum
    additional = worst_host['capacityUsed']
    free = total - used
    usedPctBeforeReMirror = 100.0 - (free.to_f * 100 / total.to_f)
    usedPctAfterReMirror = 100.0 - ((free - additional).to_f * 100 / total.to_f)
    usedPctIncrease = usedPctAfterReMirror - usedPctOriginal
    capacityRow << "%3.0f%% used (%.2f GB free)" % [
      usedPctAfterReMirror,
      (free - additional).to_f / 1024**3,
    ]
    t << capacityRow
    
    # Components before failure
    sorted_hosts = hosts_disks.values.sort_by{|x| -x['lsom_objects_count']}
    worst_host = sorted_hosts[0]
    used = sorted_hosts.map{|x| x['lsom_objects_count']}.sum
    total = sorted_hosts.map{|x| x['maxComponents']}.sum
    free = total - used
    usedPctOriginal = 100.0 - (free.to_f * 100 / total.to_f)
    componentsRow = ["Components"]
    componentsRow << "%3.0f%% used (%u available)" % [
      usedPctOriginal,
      free,
    ]

    # Components after rebuild
    used = sorted_hosts[1..-1].map{|x| x['lsom_objects_count']}.sum
    total = sorted_hosts[1..-1].map{|x| x['maxComponents']}.sum
    additional = worst_host['lsom_objects_count']
    free = total - used
    usedPctBeforeReMirror = 100.0 - (free.to_f * 100 / total.to_f)
    usedPctAfterReMirror = 100.0 - ((free - additional).to_f * 100 / total.to_f)
    usedPctIncrease = usedPctAfterReMirror - usedPctOriginal
    componentsRow << "%3.0f%% used (%u available)" % [
      usedPctAfterReMirror,
      (free - additional),
    ]
    t << componentsRow

    # RC reservations before failure
    sorted_hosts = hosts_disks.values.sort_by{|x| -x['ssd_capacityReserved']}
    worst_host = sorted_hosts[0]
    used = sorted_hosts.map{|x| x['ssd_capacityReserved']}.sum
    total = sorted_hosts.map{|x| x['ssd_capacity']}.sum
    free = total - used
    usedPctOriginal = 100.0 - (free.to_f * 100 / total.to_f)
    rcReservationsRow = ["RC reservations"]
    rcReservationsRow << "%3.0f%% used (%.2f GB free)" % [
      usedPctOriginal,
      free.to_f / 1024**3,
    ]

    # RC reservations after rebuild
    used = sorted_hosts[1..-1].map{|x| x['ssd_capacityReserved']}.sum
    total = sorted_hosts[1..-1].map{|x| x['ssd_capacity']}.sum
    additional = worst_host['ssd_capacityReserved']
    free = total - used
    usedPctBeforeReMirror = 100.0 - (free.to_f * 100 / total.to_f)
    usedPctAfterReMirror = 100.0 - ((free - additional).to_f * 100 / total.to_f)
    usedPctIncrease = usedPctAfterReMirror - usedPctOriginal
    rcReservationsRow << "%3.0f%% used (%.2f GB free)" % [
      usedPctAfterReMirror,
      (free - additional).to_f / 1024**3,
    ]
    t << rcReservationsRow
        
    puts t
  end
end


def _observe_snapshot conn, host, hosts, vmView, pc, hosts_props, vsanIntSys
  startTime = Time.now
  observation = {
    'cmmds' => {
      'clusterInfos' => {},
      'clusterDirs' => {},
    },
    'vsi' => {},
    'inventory' => {},
  }
  exceptions = []
  threads = []
  begin
  threads << Thread.new do 
    begin
      t1 = Time.now
      vms = vmView.view
      
      vmProperties = [
        'name', 'runtime.powerState', 'datastore', 'config.annotation',
        'parent', 'resourcePool', 'storage.perDatastoreUsage',
        'summary.config.memorySizeMB', 'summary.config.numCpu',
        'summary.config.vmPathName', 'config.hardware.device',
        'runtime.connectionState',
      ]
      vmsProps = pc.collectMultiple(vms, *vmProperties)
      t2 = Time.now
      puts "Query VM properties: %.2f sec" % (t2 - t1)
      observation['inventory']['vms'] = {}
      vmsProps.each do |vm, vmProps|
        vmProps['vsan-obj-uuids'] = {}
        devices = vmProps['config.hardware.device'] || []
        disks = devices.select{|x| x.is_a?(VIM::VirtualDisk)}
        disks.each do |disk|
          newBacking = {}
          newDisk = {
            'unitNumber' => disk.unitNumber,
            'controllerKey' => disk.controllerKey,
            'backing' => newBacking,  
          }
          backing = disk.backing
          if !backing.is_a?(VIM::VirtualDiskFlatVer2BackingInfo)
            next
          end
          while backing
            uuid = backing.backingObjectId
            if uuid
              vmProps['vsan-obj-uuids'][uuid] = backing.fileName
              newBacking['uuid'] = uuid
            end
            newBacking['fileName'] = backing.fileName
            backing = backing.parent
            
            if backing
              newBacking['parent'] = {}
              newBacking = newBacking['parent']
            end
          end
          
          vmProps['disks'] ||= []
          vmProps['disks'] << newDisk
        end
        # Do not add devices to the snapshot as they are too big
        vmProps.delete('config.hardware.device')
        
        begin
          vmPathName = vmProps['summary.config.vmPathName']
          uuid = vmPathName.split("] ")[1].split("/")[0]
          vmProps['vsan-obj-uuids'][uuid] = vmPathName
        rescue
        end
        
        observation['inventory']['vms'][vm._ref] = vmProps
      end
    rescue Exception => ex
      exceptions << ex
    end
  end
  threads << Thread.new do 
    begin
      sleep(20)
      hostname = hosts_props[host]['name'] 
      # XXX: Should pick one host per partition
      c1 = conn.spawn_additional_connection
      vsanIntSys1  = vsanIntSys.dup_on_conn(c1)
      
      t1 = Time.now
      res = vsanIntSys1.query_cmmds(
        (1..30).map{|x| {:type => x}}
      )
      t2 = Time.now
      puts "Query CMMDS from #{hostname}: %.2f sec (json size: %dKB)" % [
        (t2 - t1), JSON.dump(res).length / 1024
      ] 
      observation['cmmds']['clusterDirs'][hostname] = res
    rescue Exception => ex
      exceptions << ex
    end
  end
  hosts.each do |host|
    threads << Thread.new do 
      begin
        hostname = hosts_props[host]['name'] 
        vsanIntSys1 = hosts_props[host]['configManager.vsanInternalSystem']
        c1 = conn.spawn_additional_connection
        vsanIntSys1  = vsanIntSys1.dup_on_conn(c1)
        
        t1 = Time.now
        res = vsanIntSys1.QueryVsanStatistics(:labels => 
          [
            'dom', 'lsom', 'worldlets', 'plog', 
            'dom-objects',
            'mem', 'cpus', 'slabs',
            'vscsi', 'cbrc',
            'disks',
            #'rdtassocsets', 
            'system-mem', 'pnics',
          ]
        )
        t2 = Time.now
        res = JSON.load(res)
        puts "Query Stats on #{host.name}: %.2f sec (on ESX: %.2f, json size: %dKB)" % [
          (t2 - t1), res['on-esx-collect-duration'],
          JSON.dump(res).length / 1024
        ]
        observation['vsi'][hostname] = res
      rescue Exception => ex
        exceptions << ex
      end
    end
  end
  threads.each{|x| x.join}
  if exceptions.length > 0
    raise exceptions.first
  end
  rescue Interrupt
    threads.each{|t| t.terminate}
  end
  
  {
    'type' => 'inventory-snapshot',
    'snapshot' => observation,
    'starttime' => startTime.to_f,
    'endtime' => Time.now.to_f,
  }
end

class VsanObserver
  def generate_observer_html(tasksAnalyzer, inventoryAnalyzer, 
                             vcInfo, hosts_props)
    opts = {}
    refreshString = ""
    vcOS = vcInfo['about']['osType']
    vcFullName = vcInfo['about']['fullName']
    testTitleString = "VC #{vcInfo['hostname']} (#{vcFullName} - #{vcOS})"
    skipTasksTab = true
    graphUpdateMsg = "XXX"
    processed = 0
    puts "#{Time.now}: Generating HTML"
    inventoryAnalyzerTabs = inventoryAnalyzer.generateHtmlTabs(
      true, 
      :skipLivenessTab => true,
      :skipLsomExpert => true,
    )
    puts "#{Time.now}: Generating HTML (fill in template)"
  
    erbFilename = "#{analyser_lib_dirname}/stats.erb.html"
    @erbFileContent = open(erbFilename, 'r').read
  
    template = ERB.new(@erbFileContent)
    html = template.result(binding)
    puts "#{Time.now}: HTML length: #{html.length}"
    
    html
  end
  
  def generate_observer_bundle(bundlePath, tasksAnalyzer, inventoryAnalyzer, 
                               vcInfo, hosts_props)
    require 'rubygems/package'
    tarFilename = File.join(
      bundlePath,
      "vsan-observer-#{Time.now.strftime('%Y-%m-%d.%H-%M-%S')}.tar" 
    )
    gzFilename = "%s.gz" % tarFilename 

    puts "#{Time.now}: Writing out an HTML bundle to #{gzFilename} ..." 
    tar = open(tarFilename, 'wb+')
    Gem::Package::TarWriter.new(tar) do |writer|
      inventoryAnalyzer.dump(:tar => writer)
      
      writer.add_file('stats.html', 0644) do |io|
        io.write(self.generate_observer_html(
          tasksAnalyzer, inventoryAnalyzer, vcInfo,
          hosts_props
          )
        )
      end
      
      [
        'graphs.html', 'bg_pattern.png', 'vmw_logo_white.png',
        'graphs.js', 'observer.css', 'vm-graph.svg'
      ].each do |filename|
        writer.add_file(filename, 0644) do |io|
          content = open("#{analyser_lib_dirname}/#{filename}", "r") do |src|
            src.read
          end
          io.write(content)
        end
      end
    end
    tar.seek(0)
    
    gz = Zlib::GzipWriter.new(File.new(gzFilename, 'wb'))
    while (buffer = tar.read(10000))
      gz.write(buffer)
    end 
    tar.close
    gz.close
    FileUtils.rm(tarFilename)
    puts "#{Time.now}: Done writing HTML bundle to #{gzFilename}" 
  end    
end

require 'webrick'
class SimpleGetForm < WEBrick::HTTPServlet::AbstractServlet
  def initialize(server, tasksAnalyzer, inventoryAnalyzer, 
                 erbFileContent, vcInfo, hosts_props)
    super server
    @tasksAnalyzer = tasksAnalyzer 
    @inventoryAnalyzer = inventoryAnalyzer
    @erbFileContent = erbFileContent
    @vcInfo = vcInfo
    @hosts_props = hosts_props
  end
  
  # Process the request, return response
  def do_GET(request, response)
    staticFiles = [
      "/graphs.js", "/graphs.html",
      "/observer.css",
      "/vmw_logo_white.png",
      "/bg_pattern.png",
      "/vm-graph.svg"
    ]
    if request.path == "/"
      status, content_type, body = mainpage(request)
    elsif staticFiles.member?(request.path)
      status, content_type, body = servefile(request)
    # elsif request.path =~ /^\/css\//
      # status, content_type, body = servefile(request)
    elsif request.path =~ /^\/jsonstats\/(dom|pcpu|mem|lsom|vm|cmmds|misc)\/(.*).json$/
      group = $1
      file = $2
      opts = {}
      if file =~ /^(.*)_thumb$/
        file = $1
        opts[:points] = 60
      end
      status, content_type, body = servejson(group, file, opts)
    else
      super(request, response)
    end
    
    response.status = status
    response['Content-Type'] = content_type
    response.body = body
  end
  
  def servefile request
    filename = "#{analyser_lib_dirname}#{request.path}"
    content = open(filename, 'r').read
    if filename =~ /\.js$/
      return [200, "text/javascript", content]
    end
    if filename =~ /\.html$/
      return [200, "text/html", content]
    end
    if filename =~ /\.less$/
      return [200, "text/css", content]
    end
    if filename =~ /\.css$/
      return [200, "text/css", content]
    end
    if filename =~ /\.png$/
      return [200, "image/png", content]
    end
    if filename =~ /\.svg$/
      return [200, "image/svg+xml", content]
    end
    
    [404, "text/html", "Not found"]
  end
  
  def json_dump out
    @inventoryAnalyzer.json_dump out
  end
  
  def servejson group, file, opts = {}
    points = opts[:points]
    if group == "misc"
      if file =~ /^distribution$/
        out = @inventoryAnalyzer.dumpDistribution(:points => points)
        return [200, "text/json", json_dump(out)]
      end
      if file =~ /^crbc-(.*)$/
        hostname = $1
        out = @inventoryAnalyzer.dumpCbrc(hostname)
        return [200, "text/json", json_dump(out)]
      end
      if file =~ /^pnics-(.*)$/
        hostname = $1
        out = @inventoryAnalyzer.dumpPnics(hostname)
        return [200, "text/json", json_dump(out)]
      end
    end
    if group == "vm"
      if file =~ /^list$/
        out = @inventoryAnalyzer.dumpVmList()
        return [200, "text/json", json_dump(out)]
      end
      if file =~ /^vscsi-([^-]*)-(.*)$/
        disk = $1
        vm = $2
        out = @inventoryAnalyzer.dumpVscsi(vm, disk, nil, :points => points)
        return [200, "text/json", json_dump(out)]
      end
    end
    if group == "cmmds"
      if file =~ /^disks$/
        out = @inventoryAnalyzer.dumpCmmdsDisks()
        return [200, "text/json", json_dump(out)]
      end
      if file =~ /^cmmds-(.*)$/
        uuid = $1
        out = @inventoryAnalyzer.dumpCmmdsUuid(uuid)
        return [200, "text/json", json_dump(out)]
      end
    end
    if group == "dom"
      if file =~ /^domobj-(client|total|compmgr)-(.*)$/
        uuid = "#{$1}-#{$2}"
        out = @inventoryAnalyzer.dumpDom(uuid, nil, :points => points)
        return [200, "text/json", json_dump(out)]
      elsif file =~ /^domobj-(.*)$/
        uuid = $1
        out = @inventoryAnalyzer.dumpDom(uuid, nil, :points => points)
        return [200, "text/json", json_dump(out)]
      end
    end
    if group == "pcpu"
      if file =~ /^wdt-(.*)-([^-]*)$/
        hostname = $1
        wdt = $2
        out = @inventoryAnalyzer.dumpWdt(hostname, wdt, nil, :points => points)
        return [200, "text/json", json_dump(out)]
      end
      if file =~ /^pcpu-(.*)$/
        hostname = $1
        out = @inventoryAnalyzer.dumpPcpu(hostname, :points => points)
        return [200, "text/json", json_dump(out)]
      end
    end
    if group == "mem"
      if file =~ /^heaps-(.*)$/
        hostname = $1
        out = @inventoryAnalyzer.dumpHeaps(hostname, nil, :points => points)
        return [200, "text/json", json_dump(out)]
      end
      if file =~ /^slabs-(.*)$/
        hostname = $1
        out = @inventoryAnalyzer.dumpSlabs(hostname, nil, :points => points)
        return [200, "text/json", json_dump(out)]
      end
      if file =~ /^system-(.*)$/
        hostname = $1
        out = @inventoryAnalyzer.dumpSystemMem(hostname, nil, :points => points)
        return [200, "text/json", json_dump(out)]
      end
    end
    if group == "lsom"
      if file =~ /^lsomcomp-(.*)$/
        uuid = $1
        out = @inventoryAnalyzer.dumpLsomComp(uuid, nil, :points => points)
        return [200, "text/json", json_dump(out)]
      end
      if file =~ /^lsomhost-(.*)$/
        hostname = $1
        out = @inventoryAnalyzer.dumpLsomHost(hostname, nil, :points => points)
        return [200, "text/json", json_dump(out)]
      end
      if file =~ /^ssd-(.*)$/
        uuid = $1
        out = @inventoryAnalyzer.dumpSsd(uuid, nil, nil, :points => points)
        return [200, "text/json", json_dump(out)]
      end
      if file =~ /^plog-(.*)$/
        dev = $1
        out = @inventoryAnalyzer.dumpPlog(dev, nil, nil, nil, :points => points)
        return [200, "text/json", json_dump(out)]
      end
      if file =~ /^disk-(.*)$/
        dev = $1
        out = @inventoryAnalyzer.dumpDisk(dev, nil, nil, :points => points)
        return [200, "text/json", json_dump(out)]
      end
      if file =~ /^physdisk-(.*)-([^-]*)$/
        hostname = $1
        dev = $2
        out = @inventoryAnalyzer.dumpPhysDisk(hostname, dev, nil, :points => points)
        return [200, "text/json", json_dump(out)]
      end
    end
    
    [404, "text/html", "Not found"]
  end
  
  def mainpage request
    tasksAnalyzer = @tasksAnalyzer 
    inventoryAnalyzer = @inventoryAnalyzer
    
    html = VsanObserver.new.generate_observer_html(
      @tasksAnalyzer, @inventoryAnalyzer, @vcInfo, @hosts_props
    )
        
    [200, "text/html", html]
  end
end

opts :observer do
  summary "Run observer"
  arg :cluster_or_host, nil, :lookup => [VIM::ClusterComputeResource, VIM::HostSystem]
  opt :filename, "Output file path", :type => :string
  opt :port, "Port on which to run webserver", :type => :int, :default => 8010
  opt :run_webserver, "Run a webserver to view live stats", :type => :boolean
  opt :force, "Apply force", :type => :boolean
  opt :keep_observation_in_memory, "Keep observed stats in memory even when commands ends. Allows to resume later", :type => :boolean
  opt :generate_html_bundle, "Generates an HTML bundle after completion. Pass a location", :type => :string
  opt :interval, "Interval (in sec) in which to collect stats", :type => :int, :default => 60
  opt :max_runtime, "Maximum number of hours to collect stats. Caps memory usage.", :type => :int, :default => 2
end

def observer cluster_or_host, opts
  conn = cluster_or_host._connection
  pc = conn.propertyCollector
  host = cluster_or_host
  entries = []
  hostUuidMap = {}

  vcAbout = conn.serviceContent.about
  vcInfo = {
    'hostname' => conn.host,
    'about' => {
      'fullName' => vcAbout.fullName,
      'osType' => vcAbout.osType,
      'apiVersion' => vcAbout.apiVersion,
      'apiType' => vcAbout.apiType,
      'build' => vcAbout.build,
      'instanceUuid' => vcAbout.instanceUuid,
      'version' => vcAbout.version,
    },
  }    
  
  if opts[:run_webserver] && !opts[:force]
    puts "Running a webserver with unencrypted HTTP on the vCenter machine "
    puts "could pose a security risk. This tool is an experimenal debugging "
    puts "tool, which has not been audited or tested for its security."
    puts "If in doubt, you may want to create a dummy vCenter machine to run"
    puts "just this tool, instead of running the tool on your production "
    puts "vCenter machine."
    puts "In order to run the webserver, please pass --force"
    err "Force needs to be applied to run the webserver"
  end
  
  require 'rvc/observer/analyzer-lib'
  require 'rvc/observer/tasks-analyzer'
  require 'rvc/observer/inventory-analyzer'

  inventoryAnalyzer = $inventoryAnalyzer
  tasksAnalyzer = $tasksAnalyzer
  
  inventoryAnalyzer ||= InventoryAnalyzer.new
  tasksAnalyzer ||= TasksAnalyzer.new({})
  
  file = nil
  if opts[:filename]
    file = open(opts[:filename], 'a')
  end
  server = nil
  webrickThread = nil
  hosts_props = nil
  
  _run_with_rev(conn, "dev") do
    vsanIntSys = nil
    if cluster_or_host.is_a?(VIM::ClusterComputeResource)
      cluster = cluster_or_host
      hosts = cluster.host
    else
      hosts = [host]
    end
    
    hosts_props = pc.collectMultiple(hosts,
      'name', 
      'runtime.connectionState',
      'configManager.vsanSystem',
      'configManager.vsanInternalSystem',
      'summary.config.product',
      'summary.hardware'
    )
    connected_hosts = hosts_props.select do |k,v| 
      v['runtime.connectionState'] == 'connected'
    end.keys
    host = connected_hosts.first
    if !host
      err "Couldn't find any connected hosts"
    end
    vsanIntSys = hosts_props[host]['configManager.vsanInternalSystem']
    vsanSysList = Hash[hosts_props.map do |host, props| 
      [props['name'], props['configManager.vsanSystem']]
    end]
    clusterInfos = pc.collectMultiple(vsanSysList.values, 
                                      'config.clusterInfo')
    hostUuidMap = Hash[vsanSysList.map do |hostname, sys|
      [clusterInfos[sys]['config.clusterInfo'].nodeUuid, hostname] 
    end]
    
    viewMgr = conn.serviceContent.viewManager
    rootFolder = conn.serviceContent.rootFolder
    
    vmView = viewMgr.CreateContainerView(
      :container => rootFolder,
      :type => ['VirtualMachine'],
      :recursive => true
    )
    
    if opts[:run_webserver]
      erbFilename = "#{analyser_lib_dirname}/stats.erb.html"
      erbFileContent = open(erbFilename, 'r').read
      
      server = WEBrick::HTTPServer.new(:Port => opts[:port])
      server.mount(
        "/", SimpleGetForm, 
        tasksAnalyzer, inventoryAnalyzer, erbFileContent, vcInfo,
        JSON.load(JSON.dump(hosts_props))
      )
      webrickThread = Thread.new do 
        server.start
      end
    end
    
    puts "Press <Ctrl>+<C> to stop observing at any point ..."
    puts

    startTime = Time.now
    begin
      while (Time.now - startTime) < opts[:max_runtime] * 3600
        puts "#{Time.now}: Collect one inventory snapshot"
        t1 = Time.now
        begin
          observation = _observe_snapshot(
            conn, host, connected_hosts, vmView, pc, hosts_props, vsanIntSys
          )
          observation['snapshot']['vcinfo'] = vcInfo
          observation['timestamp'] = Time.now.to_f
          if file
            file.write(JSON.dump(observation) + "\n")
            file.flush()
          else
            puts "#{Time.now}: Live-Processing inventory snapshot"
            tasksAnalyzer.processTrace(observation)
            inventoryAnalyzer.processInventorySnapshot(observation)
          end
        rescue Interrupt
          raise
        rescue Exception => ex
          puts "#{Time.now}: Got exception: #{ex.class}: #{ex.message}"
        end
        t2 = Time.now
        
        intervalTime = opts[:interval]
        time = t2 - t1
        sleepTime = intervalTime - time
        if sleepTime <= 0.0
          puts "#{Time.now}: Collection took %.2fs (> %.2fs), no sleep ..." % [
            time, intervalTime
          ]
        else
          puts "#{Time.now}: Collection took %.2fs, sleeping for %.2fs" % [
            time, sleepTime
          ]
          puts "#{Time.now}: Press <Ctrl>+<C> to stop observing"
          sleep(sleepTime)
        end
      end
    rescue Interrupt
      puts "#{Time.now}: Execution interrupted, wrapping up ..."
    end
    #pp res
    vmView.DestroyView()
    
  end
  
  if file
    file.close()
  end
  if server
    server.shutdown
    webrickThread.join
  end
  if opts[:generate_html_bundle] 
    begin
      VsanObserver.new.generate_observer_bundle(
        opts[:generate_html_bundle], tasksAnalyzer, inventoryAnalyzer, 
        vcInfo, hosts_props
      )
    rescue Exception => ex
      puts "#{Time.now}: Failed to generate HTML bundle: #{ex.class}: #{ex.message}"
    end
  end
  
  if opts[:keep_observation_in_memory]
    $inventoryAnalyzer = inventoryAnalyzer
    $tasksAnalyzer = tasksAnalyzer
  else
    $inventoryAnalyzer = nil
    $tasksAnalyzer = nil
  end
end

class RbVmomi::VIM
  def initialize opts
    super opts
  end
  
  def spawn_additional_connection
    c1 = RbVmomi::VIM.new(@opts)
    c1.cookie = self.cookie
    c1.rev = self.rev
    c1
  end
end

RbVmomi::VIM::ManagedObject
class RbVmomi::VIM::ManagedObject
  def dup_on_conn conn
    self.class.new(conn, self._ref)
  end
end


opts :resync_dashboard do
  summary "Resyncing dashboard"
  arg :cluster_or_host, nil, :lookup => [VIM::ClusterComputeResource, VIM::HostSystem]
  opt :refresh_rate, "Refresh interval (in sec). Default is no refresh", :type => :int
end

def resync_dashboard cluster_or_host, opts
  conn = cluster_or_host._connection
  pc = conn.propertyCollector
  if cluster_or_host.is_a?(VIM::ClusterComputeResource)
    cluster = cluster_or_host
    hosts = cluster.host
  else
    hosts = [host]
  end

  _run_with_rev(conn, "dev") do 
    hosts_props = pc.collectMultiple(hosts,
      'name', 
      'runtime.connectionState',
      'configManager.vsanSystem',
      'configManager.vsanInternalSystem'
    )
    connected_hosts = hosts_props.select do |k,v| 
      v['runtime.connectionState'] == 'connected'
    end.keys
    host = connected_hosts.first
    if !host
      err "Couldn't find any connected hosts"
    end
    hostname = hosts_props[host]['name']
    vsanIntSys = hosts_props[host]['configManager.vsanInternalSystem']

    vsanSysList = Hash[hosts_props.map do |host, props| 
      [props['name'], props['configManager.vsanSystem']]
    end]
    clusterInfos = pc.collectMultiple(vsanSysList.values, 
                                      'config.clusterInfo')
    hostUuidMap = Hash[vsanSysList.map do |hostname, sys|
      [clusterInfos[sys]['config.clusterInfo'].nodeUuid, hostname] 
    end]
  
    entries = nil
  
    puts "#{Time.now}: Querying all VMs on VSAN ..."
    ds_list = host.datastore
    ds_props = pc.collectMultiple(ds_list, 'name', 'summary.type')
    ds = ds_props.select{|k, x| x['summary.type'] == "vsan"}.keys.first
    ds_name = ds_props[ds]['name']
    
    vms = ds.vm
    vmsProps = pc.collectMultiple(vms, 
      'name', 'runtime.connectionState',
      'config.hardware.device', 'summary.config'
    )
    
    iter = 0
    while (iter == 0) || opts[:refresh_rate]
      puts "#{Time.now}: Querying all objects in the system from #{hostname} ..."
      
      result = vsanIntSys.query_syncing_vsan_objects({})
      if !result
        err "Server failed to gather syncing objects"
      end
      objects = result['dom_objects']
      
      puts "#{Time.now}: Got all the info, computing table ..."
      objects = objects.map do |uuid, objInfo|
        obj = objInfo['config']
        comps = _components_in_dom_config(obj['content'])
        bytesToSyncTotal = 0
        recoveryETATotal = 0
        comps = comps.select do |comp|
          state = comp['attributes']['componentState']
          bytesToSync = comp['attributes']['bytesToSync'] || 0
          recoveryETA = comp['attributes']['recoveryETA'] || 0
          resync = [10, 6].member?(state) && bytesToSync != 0
          if resync
            bytesToSyncTotal += bytesToSync
            recoveryETATotal = [recoveryETA, recoveryETATotal].max
          end
          resync
        end
        obj['bytesToSync'] = bytesToSyncTotal
        obj['recoveryETA'] = recoveryETATotal
        if comps.length > 0
          obj
        end
      end.compact
      obj_uuids = objects.map{|x| x['uuid']}
      objects = Hash[objects.map{|x| [x['uuid'], x]}]
      
      all_obj_uuids = []
      vmToObjMap = {}
      vms.each do |vm|
        vm_obj_uuids = _get_vm_obj_uuids(vm, vmsProps)
        vm_obj_uuids = vm_obj_uuids.select{|x, v| obj_uuids.member?(x)}
        vm_obj_uuids = vm_obj_uuids.reject{|x, v| all_obj_uuids.member?(x)}
        all_obj_uuids += vm_obj_uuids.keys
        if vm_obj_uuids.length > 0
          vmToObjMap[vm] = vm_obj_uuids
        end
      end
      
      t = Terminal::Table.new()
      t << [
        'VM/Object', 
        'Syncing objects', 
        'Bytes to sync', 
        #'ETA',
      ]
      t.add_separator
      bytesToSyncGrandTotal = 0
      objGrandTotal = 0
      vmToObjMap.each do |vm, vm_obj_uuids|
        vmProps = vmsProps[vm]
        objs = vm_obj_uuids.keys.map{|x| objects[x]}
        bytesToSyncTotal = objs.map{|obj| obj['bytesToSync']}.sum
        recoveryETATotal = objs.map{|obj| obj['recoveryETA']}.max
        t << [
          vmProps['name'], 
          objs.length,
          "", #"%.2f GB" % (bytesToSyncTotal.to_f / 1024**3),
          #"%.2f min" % (recoveryETATotal.to_f / 60),
        ]
        objs.each do |obj|
          t << [
            "   %s" % (vm_obj_uuids[obj['uuid']] || obj['uuid']), 
            '',
            "%.2f GB" % (obj['bytesToSync'].to_f / 1024**3),
            #"%.2f min" % (obj['recoveryETA'].to_f / 60),
          ]
        end
        bytesToSyncGrandTotal += bytesToSyncTotal
        objGrandTotal += objs.length
      end
      t.add_separator
      t << [
        'Total', 
        objGrandTotal,
        "%.2f GB" % (bytesToSyncGrandTotal.to_f / 1024**3),
        #"%.2f min" % (recoveryETATotal.to_f / 60),
      ]
      puts t
      iter += 1
      
      if opts[:refresh_rate]
        sleep opts[:refresh_rate]
      end
    end
  end
end

opts :vm_perf_stats do
  summary "VM perf stats"
  arg :vms, nil, :lookup => [VIM::VirtualMachine], :multi => true
  opt :interval, "Time interval to compute average over", :type => :int, :default => 20
  opt :show_objects, "Show objects that are part of VM", :type => :boolean
end

def vm_perf_stats vms, opts
  conn = vms.first._connection
  pc = conn.propertyCollector
  cluster = vms.first.runtime.host.parent
  hosts = cluster.host

  _run_with_rev(conn, "dev") do 
    hosts_props = pc.collectMultiple(hosts,
      'name', 
      'runtime.connectionState',
      'configManager.vsanSystem',
      'configManager.vsanInternalSystem'
    )
    connected_hosts = hosts_props.select do |k,v| 
      v['runtime.connectionState'] == 'connected'
    end.keys
    host = connected_hosts.first
    if !host
      err "Couldn't find any connected hosts"
    end
    vsanIntSys = hosts_props[host]['configManager.vsanInternalSystem']

    vsanSysList = Hash[hosts_props.map do |host, props| 
      [props['name'], props['configManager.vsanSystem']]
    end]
    clusterInfos = pc.collectMultiple(vsanSysList.values, 
                                      'config.clusterInfo')
    hostUuidMap = Hash[vsanSysList.map do |hostname, sys|
      [clusterInfos[sys]['config.clusterInfo'].nodeUuid, hostname] 
    end]
    hostNameToMoMap = Hash[hosts_props.map do |host, props|
      [props['name'], host]
    end]
  
    entries = nil
  
    puts "#{Time.now}: Querying info about VMs ..."
    vmsProps = pc.collectMultiple(vms, 
      'name', 'runtime.connectionState',
      'config.hardware.device', 'summary.config'
    )

    obj_uuids = []
    vms.each do |vm|
      obj_uuids += _get_vm_obj_uuids(vm, vmsProps).keys
    end
    
    puts "#{Time.now}: Querying VSAN objects used by the VMs ..."
    
    objects = vsanIntSys.query_cmmds(obj_uuids.map do |uuid|
      {:type => 'CONFIG_STATUS', :uuid => uuid}
    end)
    if !objects
      err "Server failed to gather CONFIG_STATUS entries"
    end
    
    objByHost = {}
    objects.each do |entry|
      host = hostUuidMap[entry['owner']]
      if !host
        next
      end
      host = hostNameToMoMap[host]
      if !host
        next
      end
      objByHost[host] ||= []
      objByHost[host] << entry['uuid']
    end
    
    def fetchStats(objByHost, hosts_props)
      stats = {}
      objByHost.each do |host, obj_uuids|
        vsanIntSys = hosts_props[host]['configManager.vsanInternalSystem']
        
        res = vsanIntSys.QueryVsanStatistics(:labels => obj_uuids.map do |uuid|
          "dom-object:#{uuid}"
        end)
        res = JSON.load(res)
        
        obj_uuids.each do |uuid|
          stats[uuid] = res['dom.owners.selected.stats'][uuid]
          if stats[uuid]
            stats[uuid]['ts'] = res['dom.owners.selected.stats-taken']
          end
        end
      end
      stats
    end
     
    puts "#{Time.now}: Fetching stats counters once ..."
    stats1 = fetchStats(objByHost, hosts_props)
    sleepTime = opts[:interval]
    puts "#{Time.now}: Sleeping for #{sleepTime} seconds ..."
    sleep(sleepTime)
    puts "#{Time.now}: Fetching stats counters again to compute averages ..."
    stats2 = fetchStats(objByHost, hosts_props)
    
    puts "#{Time.now}: Got all data, computing table"
    stats = {}
    objects.each do |entry|
      uuid = entry['uuid']
      deltas = Hash[stats2[uuid].keys.map do |key|
        [key, stats2[uuid][key] - stats1[uuid][key]]
      end]
      deltaT = deltas['ts']
      stats[uuid] = deltas.merge({
        :readIops => deltas['readCount'] / deltaT,
        :writeIops => deltas['writeCount'] / deltaT,
        :readTput => deltas['readBytes'] / deltaT,
        :writeTput => deltas['writeBytes'] / deltaT,
        :readLatency => 0,
        :writeLatency => 0,
      })
      if deltas['readCount'] > 0
        stats[uuid][:readLatency] = deltas['readLatencySumUs'] / deltas['readCount']
      end
      if deltas['writeCount'] > 0
        stats[uuid][:writeLatency] = deltas['writeLatencySumUs'] / deltas['writeCount']
      end
    end
    
    t = Terminal::Table.new()
    t << [
      'VM/Object', 
      'IOPS', 
      'Tput (KB/s)',
      'Latency (ms)'
    ]
    t.add_separator
    vms.each do |vm|
      vmProps = vmsProps[vm]
      vm_obj_uuids = _get_vm_obj_uuids(vm, vmsProps)

      if !opts[:show_objects]
        vmStats = {}
        vmStats[:readLatency] ||= []
        vmStats[:writeLatency] ||= []
        [:readIops, :writeIops, :readTput, :writeTput].each do |key|
          vmStats[key] ||= 0.0
        end
        
        vm_obj_uuids.each do |uuid, path|
          path = path.gsub(/^\[([^\]]*)\] /, "")
          objStats = stats[uuid]
          if !objStats
            next
          end
          [:readIops, :writeIops, :readTput, :writeTput].each do |key|
            vmStats[key] += (objStats[key] || 0.0)
          end
          vmStats[:readLatency] << (objStats[:readLatency] * objStats[:readIops])
          vmStats[:writeLatency] << (objStats[:writeLatency] * objStats[:writeIops])
        end
        if vmStats[:readLatency].length > 0 && vmStats[:readIops] > 0.0 
          vmStats[:readLatency] = vmStats[:readLatency].sum / vmStats[:readIops]
        else
          vmStats[:readLatency] = 0.0
        end
        if vmStats[:writeLatency].length > 0 && vmStats[:writeIops] > 0.0 
          vmStats[:writeLatency] = vmStats[:writeLatency].sum / vmStats[:writeIops]
        else
          vmStats[:writeLatency] = 0.0
        end
        
        t << [
          vmProps['name'], 
          [
            "%.1fr" % [vmStats[:readIops]],
            "%.1fw" % [vmStats[:writeIops]],
          ].join("/"),
          [
            "%.1fr" % [vmStats[:readTput] / 1024.0],
            "%.1fw" % [vmStats[:writeTput] / 1024.0],
          ].join("/"),
          [
            "%.1fr" % [vmStats[:readLatency] / 1000.0],
            "%.1fw" % [vmStats[:writeLatency] / 1000.0],
          ].join("/"),
        ]
      else
        t << [
          vmProps['name'], 
          "",
          "",
          "",
        ]
        vm_obj_uuids.each do |uuid, path|
          path = path.gsub(/^\[([^\]]*)\] /, "")
          objStats = stats[uuid]
          if !objStats
            t << [
              "   %s" % (path || uuid),
              "N/A","N/A","N/A",
            ]
            next 
          end
          t << [
            "   %s" % (path || uuid), 
            [
              "%.1fr" % [objStats[:readIops]],
              "%.1fw" % [objStats[:writeIops]],
            ].join("/"),
            [
              "%.1fr" % [objStats[:readTput] / 1024.0],
              "%.1fw" % [objStats[:writeTput] / 1024.0],
            ].join("/"),
            [
              "%.1fr" % [objStats[:readLatency] / 1000.0],
              "%.1fw" % [objStats[:writeLatency] / 1000.0],
            ].join("/"),
          ]
        end
      end
    end
    # t.add_separator
    # t << [
      # 'Total', 
      # objGrandTotal,
      # "%.2f GB" % (bytesToSyncGrandTotal.to_f / 1024**3),
      # #"%.2f min" % (recoveryETATotal.to_f / 60),
    # ]
    puts t
  end
end


opts :enter_maintenance_mode do
  summary "Put hosts into maintenance mode"
  arg :host, nil, :lookup => VIM::HostSystem, :multi => true
  opt :timeout, "Timeout", :default => 0
  opt :evacuate_powered_off_vms, "Evacuate powered off vms", :type => :boolean
  opt :no_wait, "Don't wait for Task to complete", :type => :boolean
  opt :vsan_mode, "Actions to take for VSAN backed storage", :type => :string, :default => "ensureObjectAccessibility"
end

def enter_maintenance_mode hosts, opts
  vsanChoices = ['ensureObjectAccessibility', 'evacuateAllData', 'noAction']
  if !vsanChoices.member?(opts[:vsan_mode])
    err "VSAN mode can only be one of these: #{vsanChoices}"
  end
  tasks = []
  conn = hosts[0]._connection
  _run_with_rev(conn, "dev") do
    tasks = hosts.map do |host|
      host.EnterMaintenanceMode_Task(
        :timeout => opts[:timeout], 
        :evacuatePoweredOffVms => opts[:evacuate_powered_off_vms],
        :maintenanceSpec => {
          :vsanMode => {
            :objectAction => opts[:vsan_mode],
          }
        }
      )
    end
  end

  if opts[:no_wait]
    # Do nothing
  else
    results = progress(tasks)
    
    results.each do |task, error|
      if error.is_a?(VIM::LocalizedMethodFault)
        state, entityName, name = task.collect('info.state', 
                                               'info.entityName',
                                               'info.name')
        puts "#{name} #{entityName}: #{error.fault.class.wsdl_name}: #{error.localizedMessage}"
        error.fault.faultMessage.each do |msg|
          puts "  #{msg.key}: #{msg.message}"
        end
        
      end
    end
  end
end

RbVmomi::VIM::HostVsanInternalSystem
class RbVmomi::VIM::HostVsanInternalSystem
  def _parseJson json
    if json == "BAD"
      return nil
    end
    begin
      json = JSON.load(json)
    rescue
      nil
    end
  end  
  
  def query_cmmds queries, opts = {}
    useGzip = (opts[:gzip]) && $vsanUseGzipApis
    if useGzip
      queries = queries + [{:type => "GZIP"}]
    end
    json = self.QueryCmmds(:queries => queries)
    if useGzip
      gzip = Base64.decode64(json)
      gz = Zlib::GzipReader.new(StringIO.new(gzip))
      json = gz.read
    end
    objects = _parseJson json
    if !objects
      raise "Server failed to gather CMMDS entries: JSON = '#{json}'"
#      raise "Server failed to gather CMMDS entries: JSON = #{json.length}"
    end
    objects = objects['result']
    objects    
  end
  
  def query_vsan_objects(opts)
    json = self.QueryVsanObjects(opts)
    objects = _parseJson json
    if !objects
      raise "Server failed to gather VSAN object info for #{obj_uuids}: JSON = '#{json}'"
    end
    objects    
  end
  
  def query_syncing_vsan_objects(opts = {})
    json = self.QuerySyncingVsanObjects(opts)
    objects = _parseJson json
    if !objects
      raise "Server failed to query syncing objects: JSON = '#{json}'"
    end
    objects    
  end

  def query_vsan_statistics(opts = {})
    json = self.QueryVsanStatistics(opts)
    objects = _parseJson json
    if !objects
      raise "Server failed to query vsan stats: JSON = '#{json}'"
    end
    objects    
  end
  
  def query_physical_vsan_disks(opts)
    json = self.QueryPhysicalVsanDisks(opts)
    objects = _parseJson json
    if !objects
      raise "Server failed to query vsan disks: JSON = '#{json}'"
    end
    objects    
  end
  
  def query_objects_on_physical_vsan_disk(opts)
    json = self.QueryObjectsOnPhysicalVsanDisk(opts)
    objects = _parseJson json
    if !objects
      raise "Server failed to query objects on vsan disks: JSON = '#{json}'"
    end
    objects    
  end
  
  
end

def _parseJson json
  if json == "BAD"
    return nil
  end
  begin
    json = JSON.load(json)
  rescue
    nil
  end
end  

def _assessAvailabilityByStatus state
  mask = {
    'DATA_AVAILABLE' => (1 << 0),
    'QUORUM' => (1 << 1),
    'PERF_COMPLIANT' => (1 << 2),
    'INCOMPLETE' => (1 << 3),
  }
  Hash[mask.map{|k,v| [k, (state & v) != 0]}]
end

opts :lldpnetmap do
  summary "Gather LLDP mapping information from a set of hosts"
  arg :hosts_and_clusters, nil, :lookup => [VIM::HostSystem, VIM::ClusterComputeResource], :multi => true
end

def lldpnetmap hosts_and_clusters, opts = {}
  conn = hosts_and_clusters.first._connection
  hosts = hosts_and_clusters.select{|x| x.is_a?(VIM::HostSystem)}
  clusters = hosts_and_clusters.select{|x| x.is_a?(VIM::ClusterComputeResource)}
  pc = conn.propertyCollector
  cluster_hosts = pc.collectMultiple(clusters, 'host')
  cluster_hosts.each do |cluster, props|
    hosts += props['host']
  end
  hosts = hosts.uniq
  _run_with_rev(conn, "dev") do
    hosts_props = pc.collectMultiple(hosts, 
      'name', 
      'runtime.connectionState',
      'configManager.vsanSystem', 
      'configManager.vsanInternalSystem'
    )
    
    hosts = hosts_props.select do |k,v| 
      v['runtime.connectionState'] == 'connected'
    end.keys
    if hosts.length == 0
      err "Couldn't find any connected hosts"
    end
    
    hosts_vsansys = Hash[hosts_props.map{|k,v| [v['configManager.vsanSystem'], k]}] 
    node_uuids = pc.collectMultiple(hosts_vsansys.keys, 'config.clusterInfo.nodeUuid')
    node_uuids = Hash[node_uuids.map do |k, v| 
      [v['config.clusterInfo.nodeUuid'], hosts_vsansys[k]]
    end]
    
    puts "#{Time.now}: This operation will take 30-60 seconds ..."
    hosts_props.map do |host, props|
      Thread.new do 
        begin
          vsanIntSys = props['configManager.vsanInternalSystem']
          c1 = conn.spawn_additional_connection
          vsanIntSys  = vsanIntSys.dup_on_conn(c1)
          res = vsanIntSys.QueryVsanStatistics(:labels => ['lldpnetmap'])
          hosts_props[host]['lldpnetmap'] = JSON.parse(res)['lldpnetmap']
        rescue Exception => ex
          puts "Failed to gather lldpnetmap from #{props['name']}: #{ex.class}: #{ex.message}"
        end
      end
    end.each{|t| t.join}
    
    t = Terminal::Table.new()
    t << ['Host', 'LLDP info']
    t.add_separator
    hosts_props.each do |host, props|
      t << [
        props['name'],
        props['lldpnetmap'].map do |switch, pnics|
          "#{switch}: #{pnics.join(',')}"
        end.join("\n")
      ]
    end
    puts t
  end
end

opts :check_limits do
  summary "Gathers (and checks) counters against limits"
  arg :hosts_and_clusters, nil, :lookup => [VIM::HostSystem, VIM::ClusterComputeResource], :multi => true
end

def check_limits hosts_and_clusters, opts = {}
  conn = hosts_and_clusters.first._connection
  hosts = hosts_and_clusters.select{|x| x.is_a?(VIM::HostSystem)}
  clusters = hosts_and_clusters.select{|x| x.is_a?(VIM::ClusterComputeResource)}
  pc = conn.propertyCollector
  cluster_hosts = pc.collectMultiple(clusters, 'host')
  cluster_hosts.each do |cluster, props|
    hosts += props['host']
  end
  hosts = hosts.uniq
  _run_with_rev(conn, "dev") do
    hosts_props = pc.collectMultiple(hosts, 
      'name', 
      'runtime.connectionState',
      'configManager.vsanSystem', 
      'configManager.vsanInternalSystem'
    )
    
    hosts = hosts_props.select do |k,v| 
      v['runtime.connectionState'] == 'connected'
    end.keys
    if hosts.length == 0
      err "Couldn't find any connected hosts"
    end
    
    lock = Mutex.new
    all_disks = {}
    puts "#{Time.now}: Gathering stats from all hosts ..."
    hosts_props.map do |host, props|
      if props['runtime.connectionState'] != 'connected'
        next
      end
      hosts_props[host]['profiling'] = {}
      Thread.new do 
        vsanIntSys = props['configManager.vsanInternalSystem']
        c1 = conn.spawn_additional_connection
        vsanIntSys2  = vsanIntSys.dup_on_conn(c1)
        begin
          timeout(45) do
            t1 = Time.now 
            res = vsanIntSys2.query_vsan_statistics(
              :labels => ['rdtglobal', 'lsom-node']
            )
            t2 = Time.now
            hosts_props[host]['profiling']['rdtglobal'] = t2 - t1
            hosts_props[host]['rdtglobal'] = res['rdt.globalinfo']
            hosts_props[host]['lsom.node'] = res['lsom.node']
          end
        rescue Exception => ex
          puts "Failed to gather RDT info from #{props['name']}: #{ex.class}: #{ex.message}"
        end

        begin
          timeout(60) do 
            t1 = Time.now
            res = vsanIntSys2.QueryVsanStatistics(
              :labels => ['dom', 'dom-objects-counts']
            )
            res = JSON.parse(res)
            if res && !res['dom.owners.count']
              # XXX: Remove me later
              # This code is a fall back path in case we are dealing
              # with an old ESX host (before Nov13 2013). As we only 
              # need to be compatible with VSAN GA, we can remove this
              # code once everyone is upgraded. 
              res = vsanIntSys2.QueryVsanStatistics(
                :labels => ['dom', 'dom-objects']
              )
              res = JSON.parse(res)
              numOwners = res['dom.owners.stats'].keys.length
            else
              numOwners = res['dom.owners.count'].keys.length
            end
            t2 = Time.now
            hosts_props[host]['profiling']['domstats'] = t2 - t1
            hosts_props[host]['dom'] = {
              'numClients'=> res['dom.clients'].keys.length, 
              'numOwners'=> numOwners,
            }
          end
        rescue Exception => ex
          puts "Failed to gather DOM info from #{props['name']}: #{ex.class}: #{ex.message}"
        end
          
        begin
          timeout(45) do 
            t1 = Time.now
            disks = vsanIntSys2.QueryPhysicalVsanDisks(:props => [
              'lsom_objects_count',
              'uuid',
              'isSsd',
              'capacity',
              'capacityUsed',
            ])
            t2 = Time.now
            hosts_props[host]['profiling']['physdisk'] = t2 - t1
            disks = JSON.load(disks)
  
            # Getting the data from all hosts is kind of overkill, but
            # this way we deal with partitions and get info on all disks
            # everywhere. But we have duplicates, so need to merge.
            lock.synchronize do 
              all_disks.merge!(disks)
            end
          end
        rescue Exception => ex
          puts "Failed to gather disks info from #{props['name']}: #{ex.class}: #{ex.message}"
        end
      end
    end.compact.each{|t| t.join}
    
    # hosts_props.each do |host, props|
      # puts "#{Time.now}: Host #{props['name']}: #{props['profiling']}"
    # end
    
    puts "#{Time.now}: Gathering disks info ..."
    disks = all_disks
    vsan_disks_info = {}
    vsan_disks_info.merge!(
      _vsan_host_disks_info(Hash[hosts.map{|h| [h, hosts_props[h]['name']]}]) 
    )  
    disks.each do |k, v| 
      v['esxcli'] = vsan_disks_info[v['uuid']]
      if v['esxcli']
        v['host'] = v['esxcli']._get_property :host
        
        hosts_props[v['host']]['components'] ||= 0
        hosts_props[v['host']]['components'] += v['lsom_objects_count']
        hosts_props[v['host']]['disks'] ||= []
        hosts_props[v['host']]['disks'] << v
      end
    end
    
    t = Terminal::Table.new()
    t << ['Host', 'RDT', 'Disks']
    t.add_separator
    hosts_props.each do |host, props|
      rdt = props['rdtglobal'] || {}
      lsomnode = props['lsom.node'] || {}
      dom = props['dom'] || {}
      t << [
        props['name'],
        [
          "Assocs: #{rdt['assocCount']}/#{rdt['maxAssocCount']}",
          "Sockets: #{rdt['socketCount']}/#{rdt['maxSocketCount']}",
          "Clients: #{dom['numClients'] || 'N/A'}",
          "Owners: #{dom['numOwners'] || 'N/A'}",
        ].join("\n"),
        ([
          "Components: #{props['components']}/%s" % [
            lsomnode['numMaxComponents'] || 'N/A'
          ],
        ] + (props['disks'] || []).map do |disk|
          if disk['capacity'] > 0
            usage = disk['capacityUsed'] * 100 / disk['capacity']
            usage = "#{usage}%"
          else
            usage = "N/A"
          end
          "#{disk['esxcli'].DisplayName}: #{usage}"
        end).join("\n"),
      ]
    end
    puts t
  end
end

opts :object_reconfigure do
  summary "Reconfigure a VSAN object"
  arg :cluster, "Cluster on which to execute the reconfig", :lookup => [VIM::HostSystem, VIM::ClusterComputeResource]
  arg :obj_uuid, "Object UUID", :type => :string, :multi => true
  opt :policy, "New policy", :type => :string, :required => true
end

def object_reconfigure cluster_or_host, obj_uuids, opts
  conn = cluster_or_host._connection
  pc = conn.propertyCollector
  if cluster_or_host.is_a?(VIM::ClusterComputeResource)
    cluster = cluster_or_host
    hosts = cluster.host
  else
    hosts = [host]
  end

  _run_with_rev(conn, "dev") do 
    hosts_props = pc.collectMultiple(hosts,
      'name', 
      'runtime.connectionState',
      'configManager.vsanSystem',
      'configManager.vsanInternalSystem'
    )
    connected_hosts = hosts_props.select do |k,v| 
      v['runtime.connectionState'] == 'connected'
    end.keys
    host = connected_hosts.first
    if !host
      err "Couldn't find any connected hosts"
    end
    vsanIntSys = hosts_props[host]['configManager.vsanInternalSystem']
    
    obj_uuids.each do |uuid|
      puts "Reconfiguring '#{uuid}' to #{opts[:policy]}"
      puts vsanIntSys.ReconfigureDomObject(
        :uuid => uuid, 
        :policy => opts[:policy]
      )
    end
  end
  puts "All reconfigs initiated. Synching operation may be happening in the background"
end


opts :obj_status_report do
  summary "Print component status for objects in the cluster."
  arg :cluster_or_host, nil, :lookup => [VIM::ClusterComputeResource, VIM::HostSystem]
  opt :print_table, "Print a table of object and their status, default all objects",
      :short => 't', :type => :boolean, :default => false
  opt :filter_table, "Filter the obj table based on status displayed in histogram, e.g. 2/3",
      :short => 'f', :type => :string, :default => nil
  opt :print_uuids, "In the table, print object UUIDs instead of vmdk and vm paths",
      :short => 'u', :type => :boolean, :default => false
  opt :ignore_node_uuid, "Estimate the status of objects if all comps on a given host were healthy.",
      :short => 'i', :type => :string, :default => nil
end

def obj_status_report cluster_or_host, opts
  conn = cluster_or_host._connection
  pc = conn.propertyCollector
  if cluster_or_host.is_a?(VIM::ClusterComputeResource)
    cluster = cluster_or_host
    hosts = cluster.host
  else
    hosts = [host]
  end

  _run_with_rev(conn, "dev") do 
    hosts_props = pc.collectMultiple(hosts,
      'name', 
      'runtime.connectionState',
      'configManager.vsanSystem',
      'configManager.vsanInternalSystem'
    )
    connected_hosts = hosts_props.select do |k,v| 
      v['runtime.connectionState'] == 'connected'
    end.keys
    host = connected_hosts.first
    if !host
      err "Couldn't find any connected hosts"
    end
    vsanIntSys = hosts_props[host]['configManager.vsanInternalSystem']

    vsanSysList = Hash[hosts_props.map do |host, props| 
      [props['name'], props['configManager.vsanSystem']]
    end]
    clusterInfos = pc.collectMultiple(vsanSysList.values, 
                                      'config.clusterInfo')
    hostUuidMap = Hash[vsanSysList.map do |hostname, sys|
      [clusterInfos[sys]['config.clusterInfo'].nodeUuid, hostname] 
    end]
  
    entries = nil
  
    puts "#{Time.now}: Querying all VMs on VSAN ..."
    ds_list = host.datastore
    ds_props = pc.collectMultiple(ds_list, 'name', 'summary.type')
    ds = ds_props.select{|k, x| x['summary.type'] == "vsan"}.keys.first
    ds_name = ds_props[ds]['name']
    
    vms = ds.vm
    vmsProps = pc.collectMultiple(vms, 
      'name', 'runtime.connectionState',
      'config.hardware.device', 'summary.config'
    )
    
    hostname = hosts_props[host]['name']
    puts "#{Time.now}: Querying all objects in the system from #{hostname} ..."
    
    objects = vsanIntSys.query_cmmds([
      {:type => 'DOM_OBJECT'}
    ], :gzip => true)
    if !objects
      err "Server failed to gather DOM_OBJECT entries"
    end
    
    puts "#{Time.now}: Querying all disks in the system ..."
    # Need a list of live disk uuids to see if components are orphaned.
    liveDisks = vsanIntSys.query_cmmds([{:type => 'DISK'}])
    liveDisks = liveDisks.select do |disk|
      disk['health'] == "Healthy"
    end.map do |disk|
      disk['uuid']
    end

    puts "#{Time.now}: Querying all components in the system ..."
    # Need a list of live comp uuids to see if components are orphaned.
    liveComps = vsanIntSys.query_cmmds(
      [{:type => 'LSOM_OBJECT'}], 
      :gzip => true
    )
    liveComps = liveComps.select do |comp|
      comp['health'] == "Healthy"
    end
    liveComps = liveComps.map do |comp|
      comp['uuid']
    end

    #pp liveDisks
    #puts "%d comps total" % liveComps.length

    puts "#{Time.now}: Got all the info, computing table ..."
    
    results = {}
    orphanRes = {}
    totalObjects = objects.length
    totalOrphans = 0

    objects = objects.select do |obj|
      comps = _components_in_dom_config(obj['content'])
      numHealthy = 0
      numDeletedComps = 0

      comps.each do |comp|
        state = comp['attributes']['componentState']
        bytesToSync = comp['attributes']['bytesToSync'] || 0
        resync = [10, 6].member?(state) && bytesToSync != 0

        # Should we count resyncing as healthy?  For now, lets do that.
        if resync || state == 5 ||
           (opts[:ignore_node_uuid] &&
            comp['attributes']['ownerId'] == opts[:ignore_node_uuid])
          numHealthy += 1
        elsif liveDisks.member?(comp['diskUuid']) &&
              !liveComps.member?(comp['componentUuid'])
          # A component is considered deleted if it's disk is present
          # and the component is not present in CMMDS.
          numDeletedComps += 1
        end
      end
      obj['numHealthy'] = numHealthy
      obj['numComps'] = comps.length
      status = [numHealthy, comps.length]

      # An object can be orphaned if it is deleted while a minority of
      # components are absent.  To consider this an orphan, the total
      # number of provably deleted components must be a quorum.
      # If we have some deleted comps, but not a quorum, then mark it
      # as an orphanCandidate instead of a full orphan.  Orphan candidates
      # still go into the normal results table.
      isOrphan = numDeletedComps > 0 && numDeletedComps > comps.length / 2
      if isOrphan
        obj['isOrphan'] = true
      elsif numDeletedComps > 0
        obj['isOrphanCandidate'] = true
      end

      if isOrphan
        # All absent components are orphaned.  Consider the object orphaned.
        totalOrphans += 1
        orphanRes[status] ||= 0
        orphanRes[status] += 1
      else
        results[status] ||= 0
        results[status] += 1
      end

      if opts[:filter_table]
        ("%d/%d" % [numHealthy, comps.length]) == opts[:filter_table]
      else
        true
      end
    end
    obj_uuids = objects.map{|x| x['uuid']}
    objectUuidMap = Hash[objects.map{|x| [x['uuid'], x]}]

    all_obj_uuids = []
    vmToObjMap = {}
    vms.each do |vm|
      vm_obj_uuids = _get_vm_obj_uuids(vm, vmsProps)
      vm_obj_uuids = vm_obj_uuids.select{|x, v| obj_uuids.member?(x)}
      vm_obj_uuids = vm_obj_uuids.reject{|x, v| all_obj_uuids.member?(x)}
      all_obj_uuids += vm_obj_uuids.keys
      if vm_obj_uuids.length > 0
        vmToObjMap[vm] = vm_obj_uuids
      end
    end

    def printObjStatusHist results
      t = Terminal::Table.new()
      t << [
        'Num Healthy Comps / Total Num Comps',
        'Num objects with such status',
      ]
      t.add_separator

      results.each do |key,val|
        t << [
          "%d/%d" % [key[0], key[1]],
          " %d" % val,
        ]
      end
      puts t
    end

    puts ""
    puts "Histogram of component health for non-orphaned objects"
    puts ""
    printObjStatusHist(results)
    puts "Total non-orphans: %d" % (totalObjects - totalOrphans)
    puts ""
    puts ""
    puts "Histogram of component health for possibly orphaned objects"
    puts ""
    printObjStatusHist(orphanRes)
    puts "Total orphans: %d" % totalOrphans
    puts ""


    if opts[:print_table] || opts[:filter_table]
      t = Terminal::Table.new()
      t << [
        'VM/Object', 
        'objects', 
        'num healthy / total comps', 
      ]
      t.add_separator
      bytesToSyncGrandTotal = 0
      objGrandTotal = 0
      vmToObjMap.each do |vm, vm_obj_uuids|
        vmProps = vmsProps[vm]
        objs = vm_obj_uuids.keys.map{|x| objectUuidMap[x]}
        t << [
          vmProps['name'], 
          objs.length,
          "",
        ]
        objs.each do |obj|
          if opts[:print_uuids]
            objName = obj['uuid']
          else
            objName = (vm_obj_uuids[obj['uuid']] || obj['uuid'])
          end

          if obj['isOrphan']
            orphanStr = "*"
          elsif obj['isOrphanCandidate']
            orphanStr = "-"
          else
            orphanStr = ""
          end

          t << [
            "   %s" % objName,
            '',
            "%d/%d%s" % [obj['numHealthy'], obj['numComps'], orphanStr],
          ]
          objects.delete(obj)
        end
      end

      # Okay, now print the remaining UUIDs which didn't map to any VM.
      if objects.length > 0
        if vmToObjMap.length > 0
          t.add_separator
        end
        t << [
          "Unassociated objects",
          '',
          '',
        ]
      end
      objects.each do |obj|
        if obj['isOrphan']
          orphanStr = "*"
        elsif obj['isOrphanCandidate']
          orphanStr = "-"
        else
          orphanStr = ""
        end

        t << [
          "   %s" % obj['uuid'],
          '',
          "%d/%d%s" % [obj['numHealthy'], obj['numComps'], orphanStr],
        ]
      end
      puts t
      puts ""
      puts "+------------------------------------------------------------------+"
      puts "| Legend: * = all unhealthy comps were deleted (disks present)     |"
      puts "|         - = some unhealthy comps deleted, some not or can't tell |"
      puts "|         no symbol = We cannot conclude any comps were deleted    |"
      puts "+------------------------------------------------------------------+"
      puts ""
    end
  end
end


opts :apply_license_to_cluster do
  summary "Apply license to VSAN "
  arg :cluster, nil, :lookup => VIM::ClusterComputeResource
  opt :license_key, "License key to be applied to the cluster", :short => 'k', :type => :string, :required => true
  opt :null_reconfigure, "", :short => 'r', :type => :boolean, :default => true
end

def apply_license_to_cluster cluster, opts
  conn = cluster._connection
  puts "#{cluster.name}: Applying VSAN License on the cluster..."
  licenseManager = conn.serviceContent.licenseManager
  licenseAssignmentManager = licenseManager.licenseAssignmentManager
  assignment = licenseAssignmentManager.UpdateAssignedLicense(
    :entity => cluster._ref,
    :licenseKey => opts[:license_key]
  )
  if opts[:null_reconfigure]
    # Due to races in the cluster assignment mechanism in vSphere 5.5 GA a 
    # disks may or may not be auto-claimed as would normally be expected.  Doing
    # a Null-Reconfigure causes the license state to be synchronized correctly and
    # allows auto-claim to work as expected.
    puts "#{cluster.name}: Null-Reconfigure to force auto-claim..."
    spec = VIM::ClusterConfigSpecEx()
    task = cluster.ReconfigureComputeResource_Task(:spec => spec, :modify => true)
    progress([task])
    childtasks = task.child_tasks
    if childtasks && childtasks.length > 0
      progress(childtasks)
    end
  end
end


opts :check_state do
  summary "Checks state of VMs and VSAN objects"
  arg :cluster_or_host, nil, :lookup => [VIM::ClusterComputeResource, VIM::HostSystem]
  opt :refresh_state, "Not just check state, but also refresh", :type => :boolean
  opt :reregister_vms, 
      "Not just check for vms with VC/hostd/vmx out of sync but also " \
      "fix them by un-registering and re-registering them",
      :type => :boolean
end

def check_state cluster_or_host, opts
  conn = cluster_or_host._connection
  pc = conn.propertyCollector
  if cluster_or_host.is_a?(VIM::ClusterComputeResource)
    cluster = cluster_or_host
    hosts = cluster.host
  else
    hosts = [host]
  end

  _run_with_rev(conn, "dev") do 
    hosts_props = pc.collectMultiple(hosts,
      'name', 
      'runtime.connectionState',
      'configManager.vsanSystem',
      'configManager.vsanInternalSystem'
    )
    connected_hosts = hosts_props.select do |k,v| 
      v['runtime.connectionState'] == 'connected'
    end.keys
    host = connected_hosts.first
    if !host
      err "Couldn't find any connected hosts"
    end
    vsanIntSys = hosts_props[host]['configManager.vsanInternalSystem']

    vsanSysList = Hash[hosts_props.map do |host, props| 
      [props['name'], props['configManager.vsanSystem']]
    end]
    clusterInfos = pc.collectMultiple(vsanSysList.values, 
                                      'config.clusterInfo')
    hostUuidMap = Hash[vsanSysList.map do |hostname, sys|
      [clusterInfos[sys]['config.clusterInfo'].nodeUuid, hostname] 
    end]
  
    entries = nil
  
    ds_list = host.datastore
    ds_props = pc.collectMultiple(ds_list, 'name', 'summary.type')
    ds = ds_props.select{|k, x| x['summary.type'] == "vsan"}.keys.first
    ds_name = ds_props[ds]['name']
    
    vms = ds.vm
    vms_props = pc.collectMultiple(vms, 'name', 'runtime.connectionState')
    
    puts "#{Time.now}: Step 1: Check for inaccessible VSAN objects"
    
    statusses = vsanIntSys.query_cmmds([{:type => 'CONFIG_STATUS'}])
    bad = statusses.select do |x| 
      state = _assessAvailabilityByStatus(x['content']['state'])
      !state['DATA_AVAILABLE'] || !state['QUORUM']
    end
    
    if !opts[:refresh_state]
      puts "Detected #{bad.length} objects to not be inaccessible"
      bad.each do |x|
        uuid = x['uuid']
        hostname = hostUuidMap[x['owner']]
        puts "Detected #{uuid} on #{hostname} to be inaccessible"
      end
    else
      bad.group_by{|x| hostUuidMap[x['owner']]}.each do |hostname, badOnHost|
        owner = hosts_props.select{|k,v| v['name'] == hostname}.keys.first
        owner_props = hosts_props[owner]
        owner_vsanIntSys = owner_props['configManager.vsanInternalSystem']
        badOnHost.each do |x|
          uuid = x['uuid']
          puts "Detected #{uuid} to not be inaccessible, refreshing state"
        end
        if badOnHost.length > 0
          badUuids = badOnHost.map{|x| x['uuid']}
          owner_vsanIntSys.AbdicateDomOwnership(:uuids => badUuids)
        end
      end  
      puts ""
  
      puts "#{Time.now}: Step 1b: Check for inaccessible VSAN objects, again"
      statusses = vsanIntSys.query_cmmds([{:type => 'CONFIG_STATUS'}])
      bad = statusses.select do |x| 
        state = _assessAvailabilityByStatus(x['content']['state'])
        !state['DATA_AVAILABLE'] || !state['QUORUM']
      end
      bad.each do |x|
        puts "Detected #{x['uuid']} is still inaccessible"
      end
    end
    puts ""

    puts "#{Time.now}: Step 2: Check for invalid/inaccessible VMs"
    invalid_vms = vms_props.select do |k,v| 
      ['invalid', 'inaccessible', 'orphaned'].member?(v['runtime.connectionState'])
    end.keys
    tasks = []
    invalid_vms.each do |vm| 
      vm_props = vms_props[vm]
      vm_state = vm_props['runtime.connectionState']
      if !opts[:refresh_state]
        puts "Detected VM '#{vm_props['name']}' as being '#{vm_state}'"
      else
        puts "Detected VM '#{vm_props['name']}' as being '#{vm_state}', reloading ..."
        begin
          if vm_state == 'orphaned'
            path = vm.summary.config.vmPathName
            tasks << vm.reloadVirtualMachineFromPath_Task(
              :configurationPath => path
            )
          else
            vm.Reload
            vm.Reload
          end
        rescue Exception => ex
          puts "#{ex.class}: #{ex.message}"
        end
      end
    end
    tasks = tasks.compact
    if tasks.length > 0
      progress(tasks)
    end
    puts ""

    if opts[:refresh_state]
      puts "#{Time.now}: Step 2b: Check for invalid/inaccessible VMs again"
      vms_props = pc.collectMultiple(vms, 'name', 'runtime.connectionState')
      invalid_vms = vms_props.select do |k,v| 
        ['invalid', 'inaccessible', 'orphaned'].member?(v['runtime.connectionState'])
      end.keys
      invalid_vms.each do |vm| 
        vm_props = vms_props[vm]
        vm_state = vm_props['runtime.connectionState']
        puts "Detected VM '#{vm_props['name']}' as still '#{vm_state}'"
      end
      puts ""
    end

    puts "#{Time.now}: Step 3: Check for VMs for which VC/hostd/vmx" \
         " are out of sync"
    inconsistent_vms = find_inconsistent_vms(cluster_or_host)
    if opts[:reregister_vms] and not inconsistent_vms.empty?
      puts "You have chosen to fix these VMs. This involves re-registering" \
           " the VM which will cause loss of some of the management state of"\
           " this VM (for eg. storage policy, permissions, tags," \
           " scheduled tasks, etc. but NO data loss). Do you want to" \
           " continue [y/N] ?"
      opt = $stdin.gets.chomp
      if opt == 'y' || opt == 'Y'
         puts "Attempting to fix these vms..."
         fix_inconsistent_vms(inconsistent_vms)
      end
    end
    puts ""

  end
end


opts :reapply_vsan_vmknic_config do
  summary "Unbinds and rebinds VSAN to its vmknics"
  arg :host, nil, :lookup => [VIM::HostSystem], :multi => true
  opt :vmknic, "Refresh a specific vmknic. default is all vmknics", :type => :string
  opt :dry_run, "Do a dry run: Show what changes would be made", :type => :boolean
end

def reapply_vsan_vmknic_config hosts, opts
  hosts.each do |host|
    hostname = host.name
    net = host.esxcli.vsan.network
    nics = net.list()
    if opts[:vmknic]
      nics = nics.select{|x| x.VmkNicName == opts[:vmknic]}
    end
    keys = {
      :AgentGroupMulticastAddress => :agentmcaddr,
      :AgentGroupMulticastPort => :agentmcport,
      :IPProtocol => nil,
      :InterfaceUUID => nil,
      :MasterGroupMulticastAddress => :mastermcaddr,
      :MasterGroupMulticastPort => :mastermcport,
      :MulticastTTL => :multicastttl,
    }
    puts "Host: #{hostname}"
    if opts[:dry_run]
      nics.each do |nic|
        puts "  Would reapply config of vmknic #{nic.VmkNicName}:"
        keys.keys.each do |key|
          puts "    #{key.to_s}: #{nic.send(key)}"
        end
      end
    else
      nics.each do |nic|
        puts "  Reapplying config of #{nic.VmkNicName}:"
        keys.keys.each do |key|
          puts "    #{key.to_s}: #{nic.send(key)}"
        end
        puts "  Unbinding VSAN from vmknic #{nic.VmkNicName} ..."
        net.ipv4.remove(:interfacename => nic.VmkNicName)
        puts "  Rebinding VSAN to vmknic #{nic.VmkNicName} ..."
        params = {
          :agentmcaddr => nic.AgentGroupMulticastAddress,
          :agentmcport => nic.AgentGroupMulticastPort,
          :interfacename => nic.VmkNicName,
          :mastermcaddr => nic.MasterGroupMulticastAddress,
          :mastermcport => nic.MasterGroupMulticastPort,
          :multicastttl => nic.MulticastTTL,
        }
        #pp params
        net.ipv4.add(params)
      end
    end
  end
end


opts :recover_spbm do
  summary "SPBM Recovery"
  arg :cluster_or_host, nil, :lookup => [VIM::ClusterComputeResource, VIM::HostSystem]
  opt :show_details, "Show all the details", :type => :boolean
end

def recover_spbm cluster_or_host, opts
  conn = cluster_or_host._connection
  pc = conn.propertyCollector
  host = cluster_or_host
  entries = []
  hostUuidMap = {}
  startTime = Time.now
  _run_with_rev(conn, "dev") do
    vsanIntSys = nil
    puts "#{Time.now}: Fetching Host info"
    if cluster_or_host.is_a?(VIM::ClusterComputeResource)
      cluster = cluster_or_host
      hosts = cluster.host
    else
      hosts = [host]
    end
    
    hosts_props = pc.collectMultiple(hosts,
      'name', 
      'runtime.connectionState',
      'configManager.vsanSystem',
      'configManager.vsanInternalSystem',
      'datastore'
    )
    connected_hosts = hosts_props.select do |k,v| 
      v['runtime.connectionState'] == 'connected'
    end.keys
    host = connected_hosts.first
    if !host
      err "Couldn't find any connected hosts"
    end
    vsanIntSys = hosts_props[host]['configManager.vsanInternalSystem']
    vsanSysList = Hash[hosts_props.map do |host, props| 
      [props['name'], props['configManager.vsanSystem']]
    end]
    clusterInfos = pc.collectMultiple(vsanSysList.values, 
                                      'config.clusterInfo')
    hostUuidMap = Hash[vsanSysList.map do |hostname, sys|
      [clusterInfos[sys]['config.clusterInfo'].nodeUuid, hostname] 
    end]
    
    puts "#{Time.now}: Fetching Datastore info"
    datastores = hosts_props.values.map{|x| x['datastore']}.flatten
    datastores_props = pc.collectMultiple(datastores, 'name', 'summary.type')
    vsanDsList = datastores_props.select do |ds, props|
      props['summary.type'] == "vsan"
    end.keys
    if vsanDsList.length > 1
      err "Two VSAN datastores found, can't handle that"
    end
    vsanDs = vsanDsList[0]
    
    puts "#{Time.now}: Fetching VM properties"
    vms = vsanDs.vm
    vms_props = pc.collectMultiple(vms, 'name', 'config.hardware.device')
    
    puts "#{Time.now}: Fetching policies used on VSAN from CMMDS"
    entries = vsanIntSys.query_cmmds([{
      :type => "POLICY",
    }], :gzip => true)
    
    policies = entries.map{|x| x['content']}.uniq

    puts "#{Time.now}: Fetching SPBM profiles"
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
    profilesMap = Hash[profiles.map do |x|
      ["#{x.profileId.uniqueId}-gen#{x.generationId}", x]
    end]
    
    puts "#{Time.now}: Fetching VM <-> SPBM profile association"
    vms_entities = vms.map do |vm|
      vm.all_pbmobjref(:vms_props => vms_props)
    end.flatten.map{|x| x.dynamicProperty = []; x}
    associatedProfiles = pm.PbmQueryAssociatedProfiles(
      :entities => vms_entities
    )
    associatedEntities = associatedProfiles.map{|x| x.object}.uniq
    puts "#{Time.now}: Computing which VMs do not have a SPBM Profile ..."
    
    nonAssociatedEntities = vms_entities - associatedEntities
    
    vmsMap = Hash[vms.map{|x| [x._ref, x]}]
    nonAssociatedVms = {}
    nonAssociatedEntities.map do |entity|
      vm = vmsMap[entity.key.split(":").first]
      nonAssociatedVms[vm] ||= []
      nonAssociatedVms[vm] << [entity.objectType, entity.key]
    end
    puts "#{Time.now}: Fetching additional info about some VMs"
    
    vms_props2 = pc.collectMultiple(vms, 'summary.config.vmPathName')

    puts "#{Time.now}: Got all info, computing after %.2f sec" % [
      Time.now - startTime
    ]
    
    policies.each do |policy|
      policy['spbmRecoveryCandidate'] = false
      policy['spbmProfile'] = nil
      if policy['spbmProfileId']
        name = "%s-gen%s" % [
          policy['spbmProfileId'],
          policy['spbmProfileGenerationNumber'],
        ]
        policy['spbmName'] = name
        policy['spbmProfile'] = profilesMap[name]
        if policy['spbmProfile']
          name = policy['spbmProfile'].name
          policy['spbmName'] = name
          name = "Existing SPBM Profile:\n#{name}"
        else
          policy['spbmRecoveryCandidate'] = true
          profile = profiles.find do |profile|
            profile.profileId.uniqueId == policy['spbmProfileId'] &&
            profile.generationId > policy['spbmProfileGenerationNumber']
          end
          # XXX: We should check if there is a profile that matches
          # one we recovered
          if profile
            name = policy['spbmProfile'].name
            name = "Old generation of SPBM Profile:\n#{name}"
          else
            name = "Unknown SPBM Profile. UUID:\n#{name}"
          end
        end
      else
        name = "Not managed by SPBM"
        policy['spbmName'] = name
      end
      propCap = policy['proportionalCapacity']
      if propCap && propCap.is_a?(Array) && propCap.length == 2
        policy['proportionalCapacity'] = policy['proportionalCapacity'][0]
      end
      
      policy['spbmDescr'] = name
    end
    entriesMap = Hash[entries.map{|x| [x['uuid'], x]}]

    nonAssociatedEntities = []
    nonAssociatedVms.each do |vm, entities|
      if entities.any?{|x| x == ["virtualMachine", vm._ref]}
        vmxPath = vms_props2[vm]['summary.config.vmPathName']
        if vmxPath =~ /^\[([^\]]*)\] ([^\/])\//
          nsUuid = $2
          entry = entriesMap[nsUuid]
          if entry && entry['content']['spbmProfileId']
            # This is a candidate
            nonAssociatedEntities << {
              :objUuid => nsUuid, 
              :type => "virtualMachine", 
              :key => vm._ref,
              :entry => entry,
              :vm => vm,
              :label => "VM Home",
            }
          end
        end
      end
      devices = vms_props[vm]['config.hardware.device']
      disks = devices.select{|x| x.is_a?(VIM::VirtualDisk)}
      disks.each do |disk|
        key = "#{vm._ref}:#{disk.key}"
        if entities.any?{|x| x == ["virtualDiskId", key]}
          objUuid = disk.backing.backingObjectId
          if objUuid
            entry = entriesMap[objUuid]
            if entry && entry['content']['spbmProfileId']
              # This is a candidate
              nonAssociatedEntities << {
                :objUuid => objUuid, 
                :type => "virtualDiskId", 
                :key => key,
                :entry => entry,
                :vm => vm,
                :label => disk.deviceInfo.label,
              }
            end
          end
        end
      end
    end
    nonAssociatedEntities.each do |entity|
      policy = policies.find do |policy|
        match = true
        ['spbmProfileId', 'spbmProfileGenerationNumber'].each do |k|
          match = match && policy[k] == entity[:entry]['content'][k]
        end
        match
      end
      entity[:policy] = policy
    end
    
    candidates = policies.select{|p| p['spbmRecoveryCandidate'] == true}

    puts "#{Time.now}: Done computing"

    if !opts[:show_details]
      puts ""
      puts "Found %d missing SPBM Profiles." % candidates.length
      puts "Found %d entities not associated with their SPBM Profiles." %  nonAssociatedEntities.length
      puts ""
      puts "You have a number of options (can be combined):"
      puts "1) Run command with --show-details to see a full report about missing"
      puts "SPBM Profiles and missing VM <-> SPBM Profile associations."
      puts "2) Run command with --create-missing-profiles to automatically create"
      puts "all missing SPBM profiles."
      puts "3)Run command with --create-missing-associations to automatically"
      puts "create all missing VM <-> SPBM Profile associations."
    end

    if opts[:show_details]
      puts "SPBM Profiles used by VSAN:"
      t = Terminal::Table.new()
      t << ['SPBM ID', 'policy']
      policies.each do |policy|
        t.add_separator
        t << [
          policy['spbmDescr'],
          policy.select{|k,v| k !~ /spbm/}.map{|k,v| "#{k}: #{v}"}.join("\n")
        ]
      end
      puts t
      puts ""
    
      if candidates.length > 0
        puts "Recreate missing SPBM Profiles using following RVC commands:"
        candidates.each do |policy|
          rules = policy.select{|k,v| k !~ /spbm/}
          s = rules.map{|k,v| "--rule VSAN.#{k}=#{v}"}.join(" ")
          puts "spbm.profile_create #{s} #{policy['spbmName']}"
        end
        puts ""
      end
    end
    
    if opts[:show_details] && nonAssociatedEntities.length > 0
      puts "Following missing VM <-> SPBM Profile associations were found:"
      t = Terminal::Table.new()
      t << ['Entity', 'VM', 'Profile']
      t.add_separator
      nonAssociatedEntities.each do |entity|
        #puts "'%s' of VM '%s' should be associated with profile '%s' but isn't." % [
        t << [
          entity[:label],
          vms_props[entity[:vm]]['name'],
          entity[:policy]['spbmName'],
        ]
        
        # Fix up the associations. Disabled for now until I can check
        # with Sudarsan
        # profile = entity[:policy]['spbmProfile']
        # if profile
          # pm.PbmAssociate(
            # :entity => PBM::PbmServerObjectRef(
              # :objectType => entity[:type],
              # :key => entity[:key],
              # :serverUuid => conn.serviceContent.about.instanceUuid
            # ), 
            # :profile => profile.profileId
          # )
        # end
      end
      puts t
    end
  end
  
end