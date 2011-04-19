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
