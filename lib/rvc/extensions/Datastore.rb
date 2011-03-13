class RbVmomi::VIM::Datastore
  def display_info
    s, info, = collect :summary, :info
    puts "type: #{s.type}"
    puts "url: #{s.accessible ? s.url : '<inaccessible>'}"
    puts "uuid: #{info.vmfs.uuid}"
    puts "multipleHostAccess: #{s.multipleHostAccess}"
    puts "capacity: %0.2fGB" % (s.capacity.to_f/10**9)
    puts "free space: %0.2fGB" % (s.freeSpace.to_f/10**9)
  end

  def self.ls_properties
    %w(name summary.capacity summary.freeSpace)
  end

  def ls_text r
    pct_used = 100*(1-(r['summary.freeSpace'].to_f/r['summary.capacity']))
    pct_used_text = "%0.1f%%" % pct_used
    capacity_text = "%0.2fGB" % (r['summary.capacity'].to_f/10**9)
    ": #{capacity_text} #{pct_used_text}"
  end

  def children
    {
      'files' => RVC::FakeDatastoreFolder.new(self, ""),
    }
  end
end

class RVC::FakeDatastoreFolder
  include RVC::InventoryObject

  attr_reader :path, :datastore

  def initialize datastore, path
    @datastore = datastore
    @path = path
  end

  def search_result_to_object x
    case x
    when RbVmomi::VIM::FolderFileInfo
      RVC::FakeDatastoreFolder.new(@datastore, "#{@path}/#{x.path}")
    when RbVmomi::VIM::FileInfo
      RVC::FakeDatastoreFile.new(@datastore, "#{@path}/#{x.path}", x)
    end
  end

  def children
    browser, ds_name = @datastore.collect :browser, :name
    results = browser.SearchDatastore_Task(
      datastorePath: "[#{ds_name}] #{@path}",
      searchSpec: {
        details: {
          fileType: true,
          fileSize: true,
          fileOwner: false,
          modification: false
        }
      }
    ).wait_for_completion

    Hash[results.file.map { |x| [x.path, search_result_to_object(x)] }]
  end

  def traverse_one arc
    browser, ds_name = @datastore.collect :browser, :name
    results = browser.SearchDatastore_Task(
      datastorePath: "[#{ds_name}] #{@path}",
      searchSpec: {
        details: {
          fileType: true,
          fileSize: true,
          fileOwner: false,
          modification: false
        },
        matchPattern: [arc]
      }
    ).wait_for_completion
    return unless results.file.size == 1
    search_result_to_object results.file[0]
  end

  def self.folder?
    true
  end

  def parent
    els = path.split '/'
    if els.empty?
      @datastore
    else
      parent_path = els[0...-1].join '/'
      RVC::FakeDatastoreFolder.new(@datastore, parent_path)
    end
  end

  def display_info
    puts "Datastore Folder"
    puts "datastore: #{@datastore.name}"
    puts "path: #{@path}"
  end
end

class RVC::FakeDatastoreFile
  include RVC::InventoryObject

  attr_reader :path, :datastore

  def initialize datastore, path, info
    @datastore = datastore
    @path = path
    @info = info
  end

  def parent
    els = path.split '/'
    parent_path = els[0...-1].join '/'
    RVC::FakeDatastoreFolder.new(@datastore, parent_path)
  end

  def display_info
    puts "Datastore File"
    puts "datastore: #{@datastore.name}"
    puts "path: #{@path}"
    puts "size: #{@info.fileSize} bytes"
    case @info
    when RbVmomi::VIM::VmConfigFileInfo
      puts "config version: #{@info.configVersion}"
    when RbVmomi::VIM::VmDiskFileInfo
      puts "capacity: #{@info.capacityKb} KB"
      puts "hardware version: #{@info.hardwareVersion}"
      puts "controller type: #{@info.controllerType}"
      puts "thin provisioned: #{@info.thin}"
      puts "type: #{@info.diskType}"
      puts "extents:\n#{@info.diskExtents.map { |x| "  #{x}" } * "\n"}"
    end
  end
end
