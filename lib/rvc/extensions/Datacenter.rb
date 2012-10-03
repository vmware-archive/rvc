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

class RbVmomi::VIM::Datacenter
  def ls_text r
    " (datacenter)"
  end

  def children
    vmFolder, datastoreFolder, networkFolder, hostFolder =
      collect *%w(vmFolder datastoreFolder networkFolder hostFolder)
    {
      'vms' => vmFolder,
      'datastores' => datastoreFolder,
      'networks' => networkFolder,
      'computers' => hostFolder,
    }
  end

  # For compatibility with previous RVC versions
  def traverse_one arc
    children = self.rvc_children
    return children[arc] if children.member? arc
    if arc == 'vm' then return vmFolder
    elsif arc == 'datastore' then return datastoreFolder
    elsif arc == 'network' then return networkFolder
    elsif arc == 'host' then return hostFolder
    end
  end

  def self.folder?
    true
  end
end
