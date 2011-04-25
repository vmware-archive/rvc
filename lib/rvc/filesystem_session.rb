module RVC

# XXX validate session name / mark keys
# XXX permissions
class FilesystemSession
  def initialize name
    @dir = File.join(Dir.tmpdir, "rvc-sessions-#{Process.uid}", name)
    FileUtils.mkdir_p @dir
    FileUtils.mkdir_p mark_dir
    FileUtils.mkdir_p connection_dir
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

