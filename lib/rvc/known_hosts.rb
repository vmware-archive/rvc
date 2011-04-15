require 'digest/sha2'
require 'fileutils'

module RVC

class KnownHosts
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
      io.write "#{hash_host protocol, hostname} #{hash_public_key public_key}"
    end
  end
end

end
