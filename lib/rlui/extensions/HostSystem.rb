require 'rlui/fake_folder'

class RbVmomi::VIM::HostSystem
  def self.ls_properties
    %w(name summary.hardware.memorySize summary.hardware.cpuModel
       summary.hardware.cpuMhz summary.hardware.numCpuPkgs
       summary.hardware.numCpuCores summary.hardware.numCpuThreads)
  end

  def self.ls_text r
    memorySize, cpuModel, cpuMhz, numCpuPkgs, numCpuCores =
      %w(memorySize cpuModel cpuMhz numCpuPkgs numCpuCores).map { |x| r["summary.hardware.#{x}"] }
    " (host): cpu #{numCpuPkgs}*#{numCpuCores}*#{"%.2f" % (cpuMhz.to_f/1000)} GHz, memory #{"%.2f" % (memorySize/10**9)} GB"
  end

  def ls_children
    {
      'vms' => RLUI::FakeFolder.new(self, :ls_vms),
      'datastores' => RLUI::FakeFolder.new(self, :ls_datastores),
    }
  end

  def ls_vms
    RLUI::Util.collect_children self, :vm
  end

  def ls_datastores
    RLUI::Util.collect_children self, :datastore
  end
end
