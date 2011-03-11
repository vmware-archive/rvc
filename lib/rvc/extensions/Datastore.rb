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

  def self.ls_text r
    pct_used = 100*(1-(r['summary.freeSpace'].to_f/r['summary.capacity']))
    pct_used_text = "%0.1f%%" % pct_used
    capacity_text = "%0.2fGB" % (r['summary.capacity'].to_f/10**9)
    ": #{capacity_text} #{pct_used_text}"
  end

  def ls_children
    {
      'files' => RVC::FakeDatastoreFolder.new(self, self, ""),
    }
  end
end

class RVC::FakeDatastoreFolder
  attr_reader :path, :datastore

  def initialize datastore, parent, path
    @datastore = datastore
    @parent = parent
    @path = path
  end

  def ls_text
    "/"
  end

  def ls_children
    # XXX optimize collect of browser and name
    results = @datastore.browser.SearchDatastore_Task(
      datastorePath: "[#{@datastore.name}] #{@path}",
      searchSpec: {
        details: {
          fileType: true,
          fileSize: true,
          fileOwner: false,
          modification: false
        }
      }
    ).wait_for_completion

    Hash[results.file.map do |x|
      case x
      when RbVmomi::VIM::FolderFileInfo
        [x.path, RVC::FakeDatastoreFolder.new(@datastore, self, "#{@path}/#{x.path}")]
      when RbVmomi::VIM::FileInfo
        [x.path, RVC::FakeDatastoreFile.new(@datastore, self, "#{@path}/#{x.path}", x)]
      end
    end]
  end

  def child_types
    Hash[ls_children.map { |k,v| [k, v.class] }]
  end

  # XXX optimize
  def traverse_one arc
    ls_children[arc]
  end

  def self.folder?
    true
  end

  def parent
    @parent
  end

  def display_info
    puts "Datastore Folder"
    puts "datastore: #{@datastore.name}"
    puts "path: #{@path}"
  end
end

class RVC::FakeDatastoreFile
  attr_reader :path, :datastore

  def initialize datastore, parent, path, info
    @datastore = datastore
    @parent = parent
    @path = path
    @info = info
  end

  def ls_text
    ""
  end

  def ls_children
    {}
  end

  def child_types
    {}
  end

  def traverse_one arc
    nil
  end

  def self.folder?
    false
  end

  def parent
    @parent
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
