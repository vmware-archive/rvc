# Copyright (c) 2011 VMware, Inc.  All Rights Reserved.

require 'tmpdir'

VMRC_NAME = "vmware-vmrc-linux-x86-3.0.0"
VMRC_PKGVER = 1
VMRC_URL = "https://github.com/downloads/vmware/rvc/#{VMRC_NAME}.#{VMRC_PKGVER}.tar.bz2"

def find_local_vmrc
  path = File.join(Dir.tmpdir, VMRC_NAME, 'plugins', 'vmware-vmrc')
  File.exists?(path) && path
end

def find_vmrc
  find_local_vmrc || search_path('vmrc')
end


opts :view do
  summary "Spawn a VMRC"
  arg :vm, nil, :lookup => VIM::VirtualMachine, :multi => true
end

rvc_alias :view
rvc_alias :view, :vmrc
rvc_alias :view, :v

def view vms
  err "VMRC not found" unless vmrc = find_vmrc
  vms.each do |vm|
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

opts :install do
  summary "Install VMRC"
end

def install
  puts "Installing VMRC..."
  system "curl -L #{VMRC_URL} | tar -xj -C #{Dir.tmpdir}" or err("VMRC installation failed")
  puts "VMRC was installed successfully."
end
