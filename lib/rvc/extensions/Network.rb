# Copyright (c) 2011 VMware, Inc.  All Rights Reserved.

class RbVmomi::VIM::Network
  def display_info
    summary, = collect(:summary)
    puts "name: #{summary.name}"
    puts "accessible: #{summary.accessible}"
    puts "IP pool name: #{summary.ipPoolName}" unless summary.ipPoolName.empty?
  end
end
