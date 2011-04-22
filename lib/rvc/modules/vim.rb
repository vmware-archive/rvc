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

require 'rvc/known_hosts'

URI_REGEX = %r{
  ^
  (?:
    ([^@:]+)
    (?::
     ([^@]*)
    )?
    @
  )?
  ([^@:]+)
  (?::(.*))?
  $
}x

opts :connect do
  summary 'Open a connection to ESX/VC'
  arg :uri, "Host to connect to"
  opt :rev, "Override protocol revision", :type => :string
end

rvc_alias :connect

def connect uri, opts
  match = URI_REGEX.match uri
  Trollop.die "invalid hostname" unless match

  username = match[1] || ENV['RBVMOMI_USER']
  password = match[2] || ENV['RBVMOMI_PASSWORD']
  host = match[3]
  path = match[4]
  bad_cert = false

  vim = nil
  loop do
    begin
      vim = RbVmomi::VIM.new :host => host,
                             :port => 443,
                             :path => '/sdk',
                             :ns => 'urn:vim25',
                             :rev => (opts[:rev]||'4.0'),
                             :ssl => true,
                             :insecure => bad_cert
      break
    rescue OpenSSL::SSL::SSLError
      # We'll check known_hosts next
      raise if bad_cert
      bad_cert = true
    rescue Errno::EHOSTUNREACH, SocketError
      err $!.message
    end
  end

  if bad_cert
    # Fall back to SSH-style known_hosts
    peer_public_key = vim.http.peer_cert.public_key
    check_known_hosts(host, peer_public_key)
  end

  unless opts[:rev]
    # negotiate API version
    rev = vim.serviceContent.about.apiVersion
    vim.rev = [rev, '4.1'].min
  end

  isVC = vim.serviceContent.about.apiType == "VirtualCenter"

  # authenticate
  if username == nil
    username = isVC ? 'Administrator' : 'root'
    puts "Using default username #{username.inspect}."
  end

  password_given = password != nil
  loop do
    begin
      password = prompt_password unless password_given
      vim.serviceContent.sessionManager.Login :userName => username,
                                              :password => password
      break
    rescue RbVmomi::VIM::InvalidLogin
      err $!.message if password_given
    end
  end

  Thread.new do
    while true
      sleep 600
      vim.serviceInstance.CurrentTime
    end
  end

  # Stash the address we used to connect so VMRC can use it.
  vim.define_singleton_method(:_host) { host }

  conn_name = host.dup
  conn_name = "#{conn_name}:1" if $shell.connections.member? conn_name
  conn_name.succ! while $shell.connections.member? conn_name

  $shell.connections[conn_name] = vim
end

def prompt_password
  ask("password: ") { |q| q.echo = false }
end

def check_known_hosts host, peer_public_key
  known_hosts = RVC::KnownHosts.new
  result, arg = known_hosts.verify 'vim', host, peer_public_key.to_s

  if result == :not_found
    puts "The authenticity of host '#{host}' can't be established."
    puts "Public key fingerprint is #{arg}."
    err "Connection failed" unless agree("Are you sure you want to continue connecting (y/n)? ", true)
    puts "Warning: Permanently added '#{host}' (vim) to the list of known hosts"
    known_hosts.add 'vim', host, peer_public_key.to_s
  elsif result == :mismatch
    err "Public key fingerprint for host '#{host}' does not match #{known_hosts.filename}:#{arg}."
  elsif result == :ok
  else
    err "Unexpected result from known_hosts check"
  end
end

class RbVmomi::VIM
  def display_info
    puts serviceContent.about.fullName
  end
end
