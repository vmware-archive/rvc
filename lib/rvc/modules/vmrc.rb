# Copyright (c) 2011 VMware, Inc.  All Rights Reserved.

# TODO windows tmp folder
def _local_vmrc_dir ver, is64
  File.join("/tmp", "vmrc-#{Process::UID.eid}-#{ver}-#{is64 ? '64' : '32'}")
end

def _find_local_vmrc vm
  ver = vm._connection.serviceInstance.content.about.version
  is64 = `uname -m`.chomp == 'x86_64'
  path = File.join(_local_vmrc_dir(ver, is64), 'plugins', 'vmware-vmrc')
  File.exists?(path) && path
end

def _find_vmrc vm
  _find_local_vmrc(vm) || search_path('vmrc')
end


opts :view do
  summary "Spawn a VMRC"
  arg :vm, nil, :lookup => VIM::VirtualMachine, :multi => true
end

rvc_alias :view
rvc_alias :view, :vmrc
rvc_alias :view, :v

def view vms
  vms.each do |vm|
    err "VMRC not found" unless vmrc = _find_vmrc(vm)
    moref = vm._ref
    ticket = vm._connection.serviceInstance.content.sessionManager.AcquireCloneTicket
    host = vm._connection._host
    fork do
      ENV['https_proxy'] = ENV['HTTPS_PROXY'] = ''
      $stderr.reopen("#{ENV['HOME']||'.'}/.rvc-vmrc.log", "w")
      $stderr.puts Time.now
      Process.setpgrp
      exec vmrc, '-M', moref,
                 '-h', host,
                 '-p', ticket
    end
  end
end
