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

class RbVmomi::VIM::HostSystem
  def self.ls_properties
    %w(name summary.hardware.memorySize summary.hardware.cpuModel
       summary.hardware.cpuMhz summary.hardware.numCpuPkgs
       summary.hardware.numCpuCores summary.hardware.numCpuThreads)
  end

  def ls_text r
    memorySize, cpuModel, cpuMhz, numCpuPkgs, numCpuCores =
      %w(memorySize cpuModel cpuMhz numCpuPkgs numCpuCores).map { |x| r["summary.hardware.#{x}"] }
    " (host): cpu #{numCpuPkgs}*#{numCpuCores}*#{"%.2f" % (cpuMhz.to_f/1000)} GHz, memory #{"%.2f" % (memorySize/10**9)} GB"
  end

  def display_info
    summary = self.summary
    runtime = summary.runtime
    stats = summary.quickStats
    hw = summary.hardware
    puts "connection state: #{runtime.connectionState}"
    puts "power state: #{runtime.powerState}"
    puts "uptime: #{"%0.2f" % ((Time.now - runtime.bootTime)/(24*3600))} days" if runtime.bootTime
    puts "in maintenance mode: #{runtime.inMaintenanceMode}"
    puts "standby mode: #{runtime.standbyMode}" if runtime.standbyMode
    if about = summary.config.product
      puts "product: #{about.fullName}"
      puts "license: #{about.licenseProductName} #{about.licenseProductVersion}" if about.licenseProductName
    end
    overallCpu = hw.numCpuPkgs * hw.numCpuCores * hw.cpuMhz
    puts "cpu: %d*%d*%.2f GHz = %.2f GHz" % [hw.numCpuPkgs, hw.numCpuCores, hw.cpuMhz/1e3, overallCpu/1e3]
    puts "cpu usage: %.2f GHz (%.1f%%)" % [stats.overallCpuUsage/1e3, 100*stats.overallCpuUsage/overallCpu]
    puts "memory: %.2f GB" % [hw.memorySize/1e9]
    puts "memory usage: %.2f GB (%.1f%%)" % [stats.overallMemoryUsage/1e3, 100*1e6*stats.overallMemoryUsage/hw.memorySize]
  end

  def children
    {
      'vms' => RVC::FakeFolder.new(self, :ls_vms),
      'datastores' => RVC::FakeFolder.new(self, :ls_datastores),
      'esxcli' => RVC::LazyEsxcliNamespace.new(self)
    }
  end

  def ls_vms
    RVC::Util.collect_children self, :vm
  end

  def ls_datastores
    RVC::Util.collect_children self, :datastore
  end
end

class RVC::LazyEsxcliNamespace
  include RVC::InventoryObject

  [:children, :traverse_one].each do |sym|
    begin
      undef_method sym
    rescue NameError
    end
  end

  def initialize host
    @host = host
    @ns = nil
  end

  def method_missing *a
    @ns ||= @host.esxcli
    @ns.send *a
  end
end

class VIM::EsxcliNamespace
  include RVC::InventoryObject

  def ls_text r
    if cli_info
      "/ - #{cli_info.help}"
    else
      "/"
    end
  end

  def children
    @namespaces.merge(Hash[@commands.map { |k,v| [k, RVC::EsxcliMethod.new(conn, self, v)] }])
  end
end

class RVC::EsxcliMethod
  include RVC::InventoryObject
  attr_reader :conn, :ns, :info

  def initialize conn, ns, info
    @conn = conn
    @ns = ns
    @info = info
  end

  def ls_text r
    " - #{cli_info.help}"
  end

  def cli_info
    @cli_info ||= @ns.cli_info.method.find { |x| x.name == info.name }
  end

  def option_parser
    parser = Trollop::Parser.new
    parser.text cli_info.help
    cli_info.param.each do |cli_param|
      vmodl_param = info.paramTypeInfo.find { |x| x.name == cli_param.name }
      opts = trollop_type(vmodl_param.type)
      opts[:required] = vmodl_param.annotation.find { |a| a.name == "optional"} ? false : true
      opts[:long] = cli_param.displayName
      #pp opts.merge(:name => cli_param.name)
      # XXX correct short options
      parser.opt cli_param.name, cli_param.help, opts
    end
    parser
  end

  def trollop_type t
    if t[-2..-1] == '[]'
      multi = true
      t = t[0...-2]
    else
      multi = false
    end
    type = case t
    when 'string', 'boolean' then t.to_sym
    when 'long' then :int
    else fail "unexpected esxcli type #{t.inspect}"
    end
    { :type => type, :multi => multi }
  end
end
