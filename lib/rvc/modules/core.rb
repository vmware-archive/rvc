opts :quit do
  summary "Exit RVC"
end

rvc_alias :quit
rvc_alias :quit, :exit
rvc_alias :quit, :q

def quit
  exit
end


opts :reload do
  summary "Reload RVC command modules and extensions"
  opt :verbose, "Display filenames loaded", :short => 'v', :default => false
end

rvc_alias :reload

def reload opts
  old_verbose = $VERBOSE
  $VERBOSE = nil unless opts[:verbose]

  RVC.reload_modules opts[:verbose]

  typenames = Set.new(VIM.loader.typenames.select { |x| VIM.const_defined? x })
  dirs = VIM.extension_dirs
  dirs.each do |path|
    Dir.open(path) do |dir|
      dir.each do |file|
        next unless file =~ /\.rb$/
        next unless typenames.member? $`
        file_path = File.join(dir, file)
        puts "loading #{$`} extensions from #{file_path}" if opts[:verbose]
        load file_path
      end
    end
  end

ensure
  $VERBOSE = old_verbose
end
