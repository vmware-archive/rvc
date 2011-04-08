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

opts :download do
  summary "Download a file from a datastore"
  arg 'datastore-path', "Filename on the datastore"
  arg 'local-path', "Filename on the local machine"
end

def download datastore_path, local_path
  file = lookup_single(datastore_path)
  err "not a datastore file" unless file.is_a? RbVmomi::VIM::Datastore::FakeDatastoreFile
  file.datastore.download file.path, local_path
end

opts :upload do
  summary "Upload a file to a datastore"
  arg 'local-path', "Filename on the local machine"
  arg 'datastore-path', "Filename on the datastore"
end

def upload local_path, datastore_path
  datastore_dir_path = File.dirname datastore_path
  dir = lookup_single(datastore_dir_path)
  err "datastore directory does not exist" unless dir.is_a? RbVmomi::VIM::Datastore::FakeDatastoreFolder
  err "local file does not exist" unless File.exists? local_path
  real_datastore_path = "#{dir.path}/#{File.basename(datastore_path)}"
  dir.datastore.upload real_datastore_path, local_path
end

opts :mkdir do
  summary "Create a directory on a datastore"
  arg 'path', "Directory to create on the datastore"
end

def mkdir datastore_path
  datastore_dir_path = File.dirname datastore_path
  dir = lookup_single(datastore_dir_path)
  err "datastore directory does not exist" unless dir.is_a? RbVmomi::VIM::Datastore::FakeDatastoreFolder
  ds = dir.datastore
  dc = ds.path.find { |o,x| o.is_a? RbVmomi::VIM::Datacenter }[0]
  name = "#{dir.datastore_path}/#{File.basename(datastore_path)}"
  dc._connection.serviceContent.fileManager.MakeDirectory :name => name,
                                                          :datacenter => dc,
                                                          :createParentDirectories => false
end
