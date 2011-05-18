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
require 'digest/sha2'
require 'zip'
require 'rbconfig'

case RbConfig::CONFIG['host_os']
when /mswin/, /mingw/
  VMRC_NAME = "vmware-vmrc-win32-x86-3.0.0-309851"
  VMRC_SHA256 = "8d8f9655121db5987bef1c2fa3a08ef2c4dd7769eb230bbd5b3ba9fd9576db56"
  VMRC_BIN = "vmware-vmrc.exe"
when /linux/
  VMRC_NAME = "vmware-vmrc-linux-x86-3.0.0-309851"
  VMRC_SHA256 = "c86ecd9d9a1dd909a119c19d28325cb87d6e2853885d3014a7dac65175dd2ae1"
  VMRC_BIN = "vmware-vmrc"
else
  VMRC_NAME = nil
  VMRC_SHA256 = nil
  VMRC_BIN = nil
  $stderr.puts "No VMRC available for OS #{RbConfig::CONFIG['host_os']}"
end

VMRC_BASENAME = "#{VMRC_NAME}.xpi"
VMRC_URL = "http://cloud.github.com/downloads/vmware/rvc/#{VMRC_BASENAME}"

def find_local_vmrc
  return nil if VMRC_NAME.nil?
  path = File.join(Dir.tmpdir, VMRC_NAME, 'plugins', VMRC_BIN)
  File.exists?(path) && path
end

def find_vmrc
  find_local_vmrc || search_path('vmrc')
end


opts :view do
  summary "Spawn a VMRC"
  text "The VMware Remote Console allows you to interact with a VM's virtual mouse, keyboard, and screen."
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
    spawn_vmrc vmrc, moref, host, ticket
  end
end

case RbConfig::CONFIG['host_os']
when /mswin/, /mingw/
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
  zip_filename = File.join(Dir.tmpdir, VMRC_BASENAME)
  download VMRC_URL, zip_filename
  verify zip_filename, VMRC_SHA256
  extract zip_filename, File.join(Dir.tmpdir, VMRC_NAME)
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
    end
  rescue Exception
    err "Error downloading VMRC: #{$!.class}: #{$!.message}"
  end
end

def verify filename, expected_hash
  puts "Checking integrity..."
  hexdigest = Digest::SHA256.file(filename).hexdigest
  err "Hash mismatch" if hexdigest != VMRC_SHA256
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
