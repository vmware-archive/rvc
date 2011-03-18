include RVC::Util

# TODO windows tmp folder
def _local_vmrc_dir ver, is64
  File.join("/tmp", "vmrc-#{Process::UID.eid}-#{ver}-#{is64 ? '64' : '32'}")
end

def _find_local_vmrc
  ver = $vim.serviceInstance.content.about.version
  is64 = `uname -m`.chomp == 'x86_64'
  path = File.join(_local_vmrc_dir(ver, is64), 'plugins', 'vmware-vmrc')
  File.exists?(path) && path
end

def _find_vmrc
  @cached_vmrc ||= ENV['VMRC'] || _find_local_vmrc || search_path('vmrc')
end

def _clear_cached_vmrc
  @cached_vmrc = nil
end

opts :view do
  summary "Spawn a VMRC"
  arg :vm, nil, :lookup => VIM::VirtualMachine, :multi => true
end

def view vms
  err "VMRC not found" unless _find_vmrc
  vms.each do |vm|
    moref = vm._ref
    fork do
      ENV['https_proxy'] = ENV['HTTPS_PROXY'] = ''
      $stderr.reopen("#{ENV['HOME']||'.'}/.rvc-vmrc.log", "w")
      $stderr.puts Time.now
      Process.setpgrp
      exec _find_vmrc, '-M', moref, '-h', $auth[:host], '-u', $auth[:username], '-p', $auth[:password]
    end
  end
end
