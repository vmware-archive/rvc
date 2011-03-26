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
      'files' => FakeDatastoreFolder.new(self, ""),
      'vms' => RVC::FakeFolder.new(self, :children_vms),
      'hosts' => RVC::FakeFolder.new(self, :children_hosts),
    }
  end

  def children_vms
    RVC::Util.collect_children self, :vm
  end

  def children_hosts
    # XXX optimize
    Hash[host.map(&:key).map { |x| [x.name, x] }]
  end
end

class RbVmomi::VIM::Datastore::FakeDatastoreFolder
  include RVC::InventoryObject

  attr_reader :path, :datastore

  def initialize datastore, path
    @datastore = datastore
    @path = path
  end

  def datastore_path
    @ds_name ||= @datastore.name
    "[#{@ds_name}] #{@path}"
  end

  def search_result_to_object x
    case x
    when RbVmomi::VIM::FolderFileInfo
      RbVmomi::VIM::Datastore::FakeDatastoreFolder.new(@datastore, "#{@path}/#{x.path}")
    when RbVmomi::VIM::FileInfo
      RbVmomi::VIM::Datastore::FakeDatastoreFile.new(@datastore, "#{@path}/#{x.path}", x)
    end
  end

  def children
    results = @datastore.browser.SearchDatastore_Task(
      :datastorePath => datastore_path,
      :searchSpec => {
        :details => {
          :fileType => true,
          :fileSize => true,
          :fileOwner => false,
          :modification => false
        }
      }
    ).wait_for_completion

    Hash[results.file.map { |x| [x.path, search_result_to_object(x)] }]
  end

  def traverse_one arc
    browser, ds_name = @datastore.collect :browser, :name
    results = browser.SearchDatastore_Task(
      :datastorePath => "[#{ds_name}] #{@path}",
      :searchSpec => {
        :details => {
          :fileType => true,
          :fileSize => true,
          :fileOwner => false,
          :modification => false
        },
        :matchPattern => [arc]
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
      RbVmomi::VIM::Datastore::FakeDatastoreFolder.new(@datastore, parent_path)
    end
  end

  def display_info
    puts "Datastore Folder"
    puts "datastore: #{@datastore.name}"
    puts "path: #{@path}"
  end

  def eql? x
    @datastore == x.instance_variable_get(:@datastore) &&
      @path == x.instance_variable_get(:@path)
  end

  def hash
    @datastore.hash ^ @path.hash
  end
end

class RbVmomi::VIM::Datastore::FakeDatastoreFile
  include RVC::InventoryObject

  attr_reader :path, :datastore

  def initialize datastore, path, info
    @datastore = datastore
    @path = path
    @info = info
  end

  def datastore_path
    @ds_name ||= @datastore.name
    "[#{@ds_name}] #{@path}"
  end

  def parent
    els = path.split '/'
    parent_path = els[0...-1].join '/'
    RbVmomi::VIM::Datastore::FakeDatastoreFolder.new(@datastore, parent_path)
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
