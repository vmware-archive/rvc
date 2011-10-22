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

module RVC

class FilesystemSession
  def initialize name
    fail "invalid session name" unless name =~ /^[\w-]+$/
    @dir = File.join(ENV['HOME'], '.rvc', 'sessions', name)
    prev_umask = File.umask 077
    FileUtils.mkdir_p @dir
    FileUtils.mkdir_p mark_dir
    FileUtils.mkdir_p connection_dir
    File.umask prev_umask
    @priv = {}
  end

  def marks
    Dir.entries(mark_dir).reject { |x| x == '.' || x == '..' } + @priv.keys
  end

  def get_mark key
    if is_private_mark? key
      @priv[key]
    else
      return nil unless File.exists? mark_fn(key)
      File.readlines(mark_fn(key)).
        map { |path| RVC::Util.lookup(path.chomp) }.
        inject([], &:+)
    end
  end

  def set_mark key, objs
    if is_private_mark? key
      if objs == nil
        @priv.delete key
      else
        @priv[key] = objs
      end
    else
      if objs == nil
        File.unlink mark_fn(key)
      else
        File.open(mark_fn(key), 'w') do |io|
          objs.each { |obj| io.puts obj.rvc_path_str }
        end
      end
    end
  end

  def connections
    Dir.entries(connection_dir).reject { |x| x == '.' || x == '..' }
  end

  def get_connection key
    return nil unless File.exists? connection_fn(key)
    File.open(connection_fn(key)) { |io| YAML.load io }
  end

  def set_connection key, conn
    if conn == nil
      File.unlink(connection_fn(key))
    else
      File.open(connection_fn(key), 'w') { |io| YAML.dump conn, io }
    end
  end

  private

  def is_private_mark? key
    return key == '' ||
           key == '~' ||
           key == '@' ||
           key =~ /^\d+$/
  end

  def mark_dir; File.join(@dir, 'marks') end
  def mark_fn(key); File.join(mark_dir, key) end
  def connection_dir; File.join(@dir, 'connections') end
  def connection_fn(key); File.join(connection_dir, key) end
end

end

