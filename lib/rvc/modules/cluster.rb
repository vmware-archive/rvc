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

opts :create do
  summary "Create a cluster"
  arg :dest, nil, :lookup_parent => VIM::Folder
end

def create dest
  folder, name = *dest
  folder.CreateClusterEx(:name => name, :spec => {})
end


opts :add_host do
  summary "Add a host to a cluster"
  arg :cluster, nil, :lookup => VIM::ClusterComputeResource
  arg :hostname, nil
  opt :username, "Username", :short => 'u', :default => 'root'
  opt :password, "Password", :short => 'p', :default => ''
end

def add_host cluster, hostname, opts
  sslThumbprint = nil
  while true
    spec = {
      :force => false,
      :hostName => hostname,
      :userName => opts[:username],
      :password => opts[:password],
      :sslThumbprint => sslThumbprint,
    }
    task = cluster.AddHost_Task :spec => spec,
                                :asConnected => true
    begin
      one_progress task
      break
    rescue VIM::SSLVerifyFault
      puts "SSL thumbprint: #{$!.fault.thumbprint}"
      $stdout.write "Accept this thumbprint? (y/n) "
      $stdout.flush
      answer = $stdin.readline.chomp
      err "Aborted" unless answer == 'y' or answer == 'yes'
      sslThumbprint = $!.fault.thumbprint
    end
  end
end


opts :configure_ha do
  summary "Configure HA on a cluster"
  arg :cluster, nil, :lookup => VIM::ClusterComputeResource
  opt :disabled, "Disable HA", :default => false
end

def configure_ha cluster, opts
  spec = VIM::ClusterConfigSpecEx(
    :dasConfig => {
      :enabled => !opts[:disabled],
    }
  )
  one_progress(cluster.ReconfigureComputeResource_Task :spec => spec, :modify => true)
end
