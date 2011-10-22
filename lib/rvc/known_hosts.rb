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

require 'digest/sha2'
require 'fileutils'
require 'rbconfig'

module RVC

class KnownHosts
  def initialize
    @ignore_permissions = RbConfig::CONFIG['host_os'] =~ /mswin|mingw/
  end

  def filename
    File.join(ENV['HOME'], ".rvc", "known_hosts");
  end

  def hash_host protocol, hostname
    Digest::SHA2.hexdigest([protocol, hostname] * "\0")
  end

  def hash_public_key public_key
    Digest::SHA2.hexdigest(public_key)
  end

  def verify protocol, hostname, public_key
    expected_hashed_host = hash_host protocol, hostname
    expected_hashed_public_key = hash_public_key public_key
    if File.exists? filename
      fail "bad permissions on #{filename}, expected 0600" unless @ignore_permissions or File.stat(filename).mode & 0666 == 0600
      File.readlines(filename).each_with_index do |l,i|
        hashed_host, hashed_public_key = l.split
        next unless hashed_host == expected_hashed_host
        if hashed_public_key == expected_hashed_public_key
          return :ok
        else
          return :mismatch, i
        end
      end
    end
    return :not_found, expected_hashed_public_key
  end

  def add protocol, hostname, public_key
    FileUtils.mkdir_p File.dirname(filename)
    File.open(filename, 'a') do |io|
      io.chmod 0600
      io.write "#{hash_host protocol, hostname} #{hash_public_key public_key}\n"
    end
  end
end

end
