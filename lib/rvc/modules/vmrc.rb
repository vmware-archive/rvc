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

require 'tmpdir'

VMRC_NAME = "vmware-vmrc-linux-x86-3.0.0"
VMRC_PKGVER = 1
VMRC_URL = "https://github.com/downloads/vmware/rvc/#{VMRC_NAME}.#{VMRC_PKGVER}.tar.bz2"

CURL = ENV['CURL'] || 'curl'

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
      $stderr.reopen("#{ENV['HOME']||'.'}/.rvc-vmrc.log", "a")
      $stderr.puts Time.now
      $stderr.puts "Using VMRC #{vmrc}"
      $stderr.flush
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
  system "#{CURL} -L #{VMRC_URL} | tar -xj -C #{Dir.tmpdir}" or err("VMRC installation failed")
  puts "VMRC was installed successfully."
end
