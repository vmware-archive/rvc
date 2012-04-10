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

require 'rvc/vim'

require 'tmpdir'
require 'digest/sha2'
require 'zip'
require 'rbconfig'

VMRC_CHECKSUMS = {
  "i686-linux" => "b8f11c92853502c3dd208da79514a66d2dd4734b8564aceb9952333037859d04",
  "x86_64-linux" => "86ec4bc6f23da0c33045d9bf48d9fe66ab2f426b523d8b37531646819891bf54",
  "i686-mswin" => "f8455f0df038fbc8e817e4381af44fa2141496cb4e2b61f505f75bc447841949",
}

PACKAGE_VERSION = 'A'
ARCH = RbConfig::CONFIG['arch']
ON_WINDOWS = (RbConfig::CONFIG['host_os'] =~ /(mswin|mingw)/) != nil

def vmrc_url arch
  "http://cloud.github.com/downloads/vmware/rvc/vmware-vmrc-public-#{arch}-#{PACKAGE_VERSION}.zip"
end

def local_vmrc_dir arch
  File.join(Dir.tmpdir, "vmware-vmrc-#{arch}-#{Process.uid}-#{PACKAGE_VERSION}")
end

def check_installed
  File.exists? local_vmrc_dir(ARCH)
end

def find_vmrc arch, version
  path = if version == '3.0.0'
    basename = ON_WINDOWS ? 'vmware-vmrc.exe' : 'vmware-vmrc'
    File.join(local_vmrc_dir(arch), version, 'plugins', basename)
  else
    fail "VMRC5 not yet supported on win32" if ON_WINDOWS
    File.join(local_vmrc_dir(arch), version, 'vmware-vmrc-5.0', 'run.sh')
  end
  File.exists?(path) && path
end

def choose_vmrc_version vim_version
  if vim_version >= '5.1.0'
    '5.0.0'
  else
    '3.0.0'
  end
end

fail unless choose_vmrc_version('4.1.0') == '3.0.0'
fail unless choose_vmrc_version('5.0.1') == '3.0.0'
fail unless choose_vmrc_version('5.1.0') == '5.0.0'
fail unless choose_vmrc_version('6.0.0') == '5.0.0'


opts :view do
  summary "Spawn a VMRC"
  text "The VMware Remote Console allows you to interact with a VM's virtual mouse, keyboard, and screen."
  opt :install, "Automatically install VMRC", :short => 'i'
  arg :vm, nil, :lookup => VIM::VirtualMachine, :multi => true
end

rvc_alias :view
rvc_alias :view, :vmrc
rvc_alias :view, :v

def view vms, opts
  conn = single_connection vms
  vim_version = conn.serviceContent.about.version
  vmrc_version = choose_vmrc_version vim_version
  unless vmrc = find_vmrc(ARCH, vmrc_version)
    if opts[:install]
      install
      vmrc = find_vmrc(ARCH, vmrc_version)
    else
      err "VMRC not found. You may need to run vmrc.install."
    end
  end

  vms.each do |vm|
    moref = vm._ref
    ticket = vm._connection.serviceInstance.content.sessionManager.AcquireCloneTicket
    host = vm._connection._host
    spawn_vmrc vmrc, moref, host, ticket
  end
end

if ON_WINDOWS
  def spawn_vmrc vmrc, moref, host, ticket
    err "Ruby 1.9 required" unless Process.respond_to? :spawn
    Process.spawn vmrc, '-h', host, '-p', ticket, '-M', moref,
                  :err => "#{ENV['HOME']||'.'}/.rvc-vmrc.log"
  end
else
  def spawn_vmrc vmrc, moref, host, ticket
    fork do
      ENV['https_proxy'] = ENV['HTTPS_PROXY'] = ''
      $stderr.reopen("#{ENV['HOME']||'.'}/.rvc-vmrc.log", "a")
      $stderr.puts Time.now
      $stderr.puts "Using VMRC #{vmrc}"
      $stderr.flush
      Process.setpgrp
      exec vmrc, '-M', moref, '-h', host, '-p', ticket
    end
  end
end


opts :install do
  summary "Install VMRC"
end

def install
  err "No VMRC available for architecture #{ARCH}" unless VMRC_CHECKSUMS.member? ARCH
  zip_filename = "#{local_vmrc_dir(ARCH)}.zip"
  url = vmrc_url ARCH
  download url, zip_filename
  verify zip_filename, VMRC_CHECKSUMS[ARCH]
  extract zip_filename, local_vmrc_dir(ARCH)
  puts "VMRC was installed successfully."
end

def download url_str, dest
  puts "Downloading VMRC..."

  url = URI.parse(url_str)

  http = if ENV['http_proxy']
    proxy_uri = URI.parse(ENV['http_proxy'])
    proxy_user, proxy_pass = proxy_uri.userinfo.split(/:/) if proxy_uri.userinfo
    Net::HTTP::Proxy(proxy_uri.host, proxy_uri.port, proxy_user, proxy_pass)
  else
    Net::HTTP
  end

  begin
    File.open(dest, 'wb') do |io|
      res = http.start(url.host, url.port) do |http|
        http.get(url.path) do |segment|
          io.write segment
        end
      end
      res.value
    end
  rescue Exception
    err "Error downloading VMRC: #{$!.class}: #{$!.message}"
  end
end

def verify filename, expected_hash
  if expected_hash == :nocheck
    puts "WARNING: skipping hash check"
  else
    puts "Checking integrity..."
    hexdigest = Digest::SHA256.file(filename).hexdigest
    err "Hash mismatch: expected #{expected_hash}, found #{hexdigest}" if hexdigest != expected_hash
  end
end

def extract src, dst
  puts "Installing VMRC..."
  FileUtils.mkdir_p dst
  Zip::ZipFile.open(src) do |zf|
    zf.each do |e|
      dst_filename = File.join(dst, e.name)
      case e.ftype
      when :file
        FileUtils.mkdir_p File.dirname(dst_filename)
        zf.extract e.name, dst_filename
        File.chmod(e.unix_perms, dst_filename) if e.unix_perms
      when :directory
        FileUtils.mkdir_p dst_filename
      else
        $stderr.puts "unknown file type #{e.ftype}"
      end
    end
  end
end
