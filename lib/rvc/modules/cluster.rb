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

require "terminal-table/import"

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
  opt :insecure, "Ignore SSL thumbprint", :short => 'k'
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
      unless opts[:insecure]
        puts "SSL thumbprint: #{$!.fault.thumbprint}"
        $stdout.write "Accept this thumbprint? (y/n) "
        $stdout.flush
        answer = $stdin.readline.chomp
        err "Aborted" unless answer == 'y' or answer == 'yes'
      end
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

opts :recommendations do
  summary "List recommendations"
  arg :cluster, nil, :lookup => VIM::ClusterComputeResource
end

def recommendations cluster
  # Collect everything we need from VC with as few calls as possible
  pc = cluster._connection.serviceContent.propertyCollector
  recommendation, hosts, datastores = cluster.collect 'recommendation', 'host', 'datastore'
  if recommendation.length == 0
    puts "None"
    return
  end
  targets = recommendation.map { |x| x.target }
  recommendation.each { |x| targets += x.action.map { |y| y.target } }
  targets += hosts
  targets += datastores
  targets.compact!
  name_map = pc.collectMultiple(targets, 'name')

  # Compose the output (tries to avoid making any API calls)
  out = table(['Key', 'Reason', 'Target', 'Actions']) do
    recommendation.each do |r|
      target_name = r.target ? name_map[r.target]['name'] : ""
      actions = r.action.map do |a|
        action = "#{a.class.wsdl_name}: #{name_map[a.target]['name']}"
        dst = nil
        if a.is_a?(RbVmomi::VIM::ClusterMigrationAction)
          dst = a.drsMigration.destination
        end
        if a.is_a?(RbVmomi::VIM::StorageMigrationAction)
          dst = a.destination
        end
        if dst
          if !name_map[dst]
            name_map[dst] = {'name' => dst.name}
          end
          action += " (to #{name_map[dst]['name']})"
        end
        action
      end
      add_row [r.key, r.reasonText, target_name, actions.join("\n")]
    end
  end
  puts out
end

opts :apply_recommendations do
  summary "Apply recommendations"
  arg :cluster, nil, :lookup => VIM::ClusterComputeResource
  opt :key, "Key of a recommendation to execute", :type => :string, :multi => true
  opt :type, "Type of actions to perform", :type => :string, :multi => true
end

def apply_recommendations cluster, opts
  pc = cluster._connection.serviceContent.propertyCollector
  recommendation = cluster.recommendation
  if opts[:key] && opts[:key].length > 0
    recommendation.select! { |x| opts[:key].member?(x.key) }
  end
  if opts[:type] && opts[:type].length > 0
    recommendation.select! { |x| (opts[:type] & x.action.map { |y| y.class.wsdl_name }).length > 0 }
  end
  all_tasks = []

  # We do recommendations in chunks, because VC can't process more than a
  # few migrations anyway and this way we get more fair queuing, less
  # timeouts of long queued migrations and a better RVC user experience
  # due to less queued tasks at a time. It would otherwise be easy to
  # exceed the screensize with queued tasks
  while recommendation.length > 0
    recommendation.pop(20).each do |r|
      targets = r.action.map { |y| y.target }
      recent_tasks = pc.collectMultiple(targets, 'recentTask')
      prev_tasks = targets.map { |x| recent_tasks[x]['recentTask'] }
      cluster.ApplyRecommendation(:key => r.key)
      recent_tasks = pc.collectMultiple(targets, 'recentTask')
      tasks = targets.map { |x| recent_tasks[x]['recentTask'] }
      all_tasks += (tasks.flatten - prev_tasks.flatten)
    end

    progress all_tasks
  end
end

