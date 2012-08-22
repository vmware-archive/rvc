def authenticate opts
  if opts[:password].nil? or opts[:password].empty?
    opts[:password] = ask("password: ") { |q| q.echo = false }
  end

  auth = VIM.NamePasswordAuthentication(
    :username => opts[:username],
    :password => opts[:password],
    :interactiveSession => opts[:interactive_session]
  )
end

# File commands
opts :chmod do
  summary "Change file attributes"
  arg :vm, nil, :lookup => VIM::VirtualMachine
  opt :group_id, "Group ID of file", :type => :int
  opt :guest_path, "Path in guest to change ownership of", :required => true, :type => :string
  opt :interactive_session, "Allow command to interact with desktop", :default => false, :type => :bool
  opt :owner_id, "Owner ID of file", :type => :int
  opt :password, "Password in guest", :type => :string
  opt :permissions, "Permissions of file", :type => :string
  opt :username, "Username in guest", :default => "root", :type => :string
end

def chmod vm, opts
  guestOperationsManager = vm._connection.serviceContent.guestOperationsManager
  err "This command requires vSphere 5 or greater" unless guestOperationsManager.respond_to? :fileManager
  fileManager = guestOperationsManager.fileManager

  opts[:permissions] = opts[:permissions].to_i(8) if opts[:permissions]

  auth = authenticate opts

  fileManager.
    ChangeFileAttributesInGuest(
      :vm => vm,
      :auth => auth,
      :guestFilePath => opts[:guest_path],
      :fileAttributes => VIM.GuestPosixFileAttributes(
        :groupId => opts[:group_id],
        :ownerId => opts[:owner_id],
        :permissions => opts[:permissions]
      )
    )
end


opts :mktmpdir do
  summary "Create temporary directory in guest"
  arg :vm, nil, :lookup => VIM::VirtualMachine
  opt :guest_path, "Path in guest to create temporary directory in", :type => :string
  opt :interactive_session, "Allow command to interact with desktop", :default => false, :type => :bool
  opt :password, "Password in guest", :type => :string
  opt :prefix, "Prefix of temporary directory", :required => true, :type => :string
  opt :suffix, "Suffix of temporary directory", :required => true, :type => :string
  opt :username, "Username in guest", :default => "root", :type => :string
end

def mktmpdir vm, opts
  guestOperationsManager = vm._connection.serviceContent.guestOperationsManager
  err "This command requires vSphere 5 or greater" unless guestOperationsManager.respond_to? :fileManager
  fileManager = guestOperationsManager.fileManager

  auth = authenticate opts

  dirname = fileManager.
    CreateTemporaryDirectoryInGuest(
      :vm => vm,
      :auth => auth,
      :prefix => opts[:prefix],
      :suffix => opts[:suffix],
      :directoryPath => opts[:guest_path]
    )
  puts dirname
  return dirname
end


opts :mktmpfile do
  summary "Create temporary file in guest"
  arg :vm, nil, :lookup => VIM::VirtualMachine
  opt :guest_path, "Path in guest to create temporary file in", :type => :string
  opt :interactive_session, "Allow command to interact with desktop", :default => false, :type => :bool
  opt :password, "Password in guest", :type => :string
  opt :prefix, "Prefix of temporary directory", :required => true, :type => :string
  opt :suffix, "Suffix of temporary directory", :required => true, :type => :string
  opt :username, "Username in guest", :default => "root", :type => :string
end

def mktmpfile vm, opts
  guestOperationsManager = vm._connection.serviceContent.guestOperationsManager
  err "This command requires vSphere 5 or greater" unless guestOperationsManager.respond_to? :fileManager
  fileManager = guestOperationsManager.fileManager

  auth = authenticate opts

  filename = fileManager.
    CreateTemporaryFileInGuest(
      :vm => vm,
      :auth => auth,
      :prefix => opts[:prefix],
      :suffix => opts[:suffix],
      :directoryPath => opts[:guest_path]
    )
  puts filename
  return filename
end


opts :rmdir do
  summary "Delete directory in guest"
  arg :vm, nil, :lookup => VIM::VirtualMachine
  opt :guest_path, "Path of directory in guest to delete", :required => true, :type => :string
  opt :interactive_session, "Allow command to interact with desktop", :default => false, :type => :bool
  opt :recursive, "Delete all subdirectories", :default => false, :type => :bool
  opt :password, "Password in guest", :type => :string
  opt :username, "Username in guest", :default => "root", :type => :string
end

def rmdir vm, opts
  guestOperationsManager = vm._connection.serviceContent.guestOperationsManager
  err "This command requires vSphere 5 or greater" unless guestOperationsManager.respond_to? :fileManager
  fileManager = guestOperationsManager.fileManager

  auth = authenticate opts

  fileManager.
    DeleteDirectoryInGuest(
      :vm => vm,
      :auth => auth,
      :directoryPath => opts[:guest_path],
      :recursive => opts[:recursive]
    )
end


opts :rmfile do
  summary "Delete file in guest"
  arg :vm, nil, :lookup => VIM::VirtualMachine
  opt :guest_path, "Path of file in guest to delete", :required => true, :type => :string
  opt :interactive_session, "Allow command to interact with desktop", :default => false, :type => :bool
  opt :password, "Password in guest", :type => :string
  opt :username, "Username in guest", :default => "root", :type => :string
end

def rmfile vm, opts
  guestOperationsManager = vm._connection.serviceContent.guestOperationsManager
  err "This command requires vSphere 5 or greater" unless guestOperationsManager.respond_to? :fileManager
  fileManager = guestOperationsManager.fileManager

  auth = authenticate opts

  fileManager.
    DeleteFileInGuest(
      :vm => vm,
      :auth => auth,
      :filePath => opts[:guest_path]
    )
end


opts :download_file do
  summary "Download file from guest"
  arg :vm, nil, :lookup => VIM::VirtualMachine
  opt :guest_path, "Path in guest to download from", :required => true, :type => :string
  opt :interactive_session, "Allow command to interact with desktop", :default => false, :type => :bool
  opt :local_path, "Local file to download to", :required => true, :type => :string
  opt :password, "Password in guest", :type => :string
  opt :username, "Username in guest", :default => "root", :type => :string
end

def download_file vm, opts
  guestOperationsManager = vm._connection.serviceContent.guestOperationsManager
  err "This command requires vSphere 5 or greater" unless guestOperationsManager.respond_to? :fileManager
  fileManager = guestOperationsManager.fileManager

  auth = authenticate opts

  download_url = fileManager.
    InitiateFileTransferFromGuest(
      :vm => vm,
      :auth => auth,
      :guestFilePath => opts[:guest_path]
    ).url

  download_uri = URI.parse(download_url.gsub /http(s?):\/\/\*:[0-9]*/, "")
  download_path = "#{download_uri.path}?#{download_uri.query}"

  http_download vm._connection, download_path, opts[:local_path]
end


opts :upload_file do
  summary "Upload file to guest"
  arg :vm, nil, :lookup => VIM::VirtualMachine
  opt :group_id, "Group ID of file", :type => :int
  opt :guest_path, "Path in guest to upload to", :required => true, :type => :string
  opt :interactive_session, "Allow command to interact with desktop", :default => false, :type => :bool
  opt :local_path, "Local file to upload", :required => true, :type => :string
  opt :overwrite, "Overwrite file", :default => false, :type => :bool
  opt :owner_id, "Owner ID of file", :type => :int
  opt :password, "Password in guest", :type => :string
  opt :permissions, "Permissions of file", :type => :string
  opt :username, "Username in guest", :default => "root", :type => :string
end

def upload_file vm, opts
  guestOperationsManager = vm._connection.serviceContent.guestOperationsManager
  err "This command requires vSphere 5 or greater" unless guestOperationsManager.respond_to? :fileManager
  fileManager = guestOperationsManager.fileManager

  opts[:permissions] = opts[:permissions].to_i(8) if opts[:permissions]

  auth = authenticate opts

  file = File.new(opts[:local_path], 'rb')

  upload_url = fileManager.
    InitiateFileTransferToGuest(
      :vm => vm,
      :auth => auth,
      :guestFilePath => opts[:guest_path],
      :fileAttributes => VIM.GuestPosixFileAttributes(
        :groupId => opts[:group_id],
        :ownerId => opts[:owner_id],
        :permissions => opts[:permissions]
      ),
      :fileSize => file.size,
      :overwrite => opts[:overwrite]
    )

  upload_uri = URI.parse(upload_url.gsub /http(s?):\/\/\*:[0-9]*/, "")
  upload_path = "#{upload_uri.path}?#{upload_uri.query}"

  http_upload vm._connection, opts[:local_path], upload_path
end


opts :ls_guest do
  summary "List files in guest"
  arg :vm, nil, :lookup => VIM::VirtualMachine
  opt :guest_path, "Path in guest to get directory listing", :required => true, :type => :string
  opt :index, "Which to start the list with", :type => :int, :default => nil
  opt :interactive_session, "Allow command to interact with desktop", :default => false, :type => :bool
  opt :match_pattern, "Filename filter (regular expression)", :type => :string
  opt :max_results, "Maximum number of results", :type => :int, :default => nil
  opt :password, "Password in guest", :type => :string
  opt :username, "Username in guest", :default => "root", :type => :string
end

def ls_guest vm, opts
  guestOperationsManager = vm._connection.serviceContent.guestOperationsManager
  err "This command requires vSphere 5 or greater" unless guestOperationsManager.respond_to? :fileManager
  fileManager = guestOperationsManager.fileManager

  auth = authenticate opts

  files = fileManager.
    ListFilesInGuest(
      :vm => vm,
      :auth => auth,
      :filePath => opts[:guest_path],
      :index => opts[:index],
      :maxResults => opts[:max_results],
      :matchPattern => opts[:match_pattern]
    )

  files.files.each do |file|
    puts file.path
  end

  puts "Remaining: #{files.remaining}" unless files.remaining.zero?

  return files
end


opts :mkdir do
  summary "Make directory in guest"
  arg :vm, nil, :lookup => VIM::VirtualMachine
  opt :guest_path, "Path of directory in guest to create", :required => true, :type => :string
  opt :interactive_session, "Allow command to interact with desktop", :default => false, :type => :bool
  opt :create_parent_directories, "Create parent directories", :default => false, :type => :bool
  opt :password, "Password in guest", :type => :string
  opt :username, "Username in guest", :default => "root", :type => :string
end

def mkdir vm, opts
  guestOperationsManager = vm._connection.serviceContent.guestOperationsManager
  err "This command requires vSphere 5 or greater" unless guestOperationsManager.respond_to? :fileManager
  fileManager = guestOperationsManager.fileManager

  auth = authenticate opts

  fileManager.
    MakeDirectoryInGuest(
      :vm => vm,
      :auth => auth,
      :directoryPath => opts[:guest_path],
      :createParentDirectories => opts[:create_parent_directories]
    )
end


opts :mvdir do
  summary "Move directory in guest"
  arg :vm, nil, :lookup => VIM::VirtualMachine
  opt :src_guest_path, "Path in guest to move from", :required => true, :type => :string
  opt :dst_guest_path, "Path in guest to move to", :required => true, :type => :string
  opt :interactive_session, "Allow command to interact with desktop", :default => false, :type => :bool
  opt :password, "Password in guest", :type => :string
  opt :username, "Username in guest", :default => "root", :type => :string
end

def mvdir vm, opts
  guestOperationsManager = vm._connection.serviceContent.guestOperationsManager
  err "This command requires vSphere 5 or greater" unless guestOperationsManager.respond_to? :fileManager
  fileManager = guestOperationsManager.fileManager

  auth = authenticate opts

  fileManager.
    MoveDirectoryInGuest(
      :vm => vm,
      :auth => auth,
      :srcDirectoryPath => opts[:src_guest_path],
      :dstDirectoryPath => opts[:dst_guest_path]
    )
end


opts :mvfile do
  summary "Move file in guest"
  arg :vm, nil, :lookup => VIM::VirtualMachine
  opt :dst_guest_path, "Path in guest to move to", :required => true, :type => :string
  opt :interactive_session, "Allow command to interact with desktop", :default => false, :type => :bool
  opt :overwrite, "Overwrite file", :default => true, :type => :bool
  opt :password, "Password in guest", :type => :string
  opt :src_guest_path, "Path in guest to move from", :required => true, :type => :string
  opt :username, "Username in guest", :default => "root", :type => :string
end

def mvfile vm, opts
  guestOperationsManager = vm._connection.serviceContent.guestOperationsManager
  err "This command requires vSphere 5 or greater" unless guestOperationsManager.respond_to? :fileManager
  fileManager = guestOperationsManager.fileManager

  auth = authenticate opts

  fileManager.
    MoveFileInGuest(
      :vm => vm,
      :auth => auth,
      :srcFilePath => opts[:src_guest_path],
      :dstFilePath => opts[:dst_guest_path],
      :overwrite => opts[:overwrite]
    )
end


# Process commands
opts :start_program do
  summary "Run program in guest"
  arg :vm, nil, :lookup => VIM::VirtualMachine
  opt :arguments, "Arguments of command", :default => "", :type => :string
  opt :background, "Don't wait for process to finish", :default => false, :type => :bool
  opt :delay, "Interval in seconds", :type => :float, :default => 5.0
  opt :env, "Environment variable(s) to set (e.g. VAR=value)", :multi => true, :type => :string
  opt :interactive_session, "Allow command to interact with desktop", :default => false, :type => :bool
  opt :password, "Password in guest", :type => :string
  opt :program_path, "Path to program in guest", :required => true, :type => :string
  opt :timeout, "Timeout in seconds", :type => :int, :default => nil
  opt :username, "Username in guest", :default => "root", :type => :string
  opt :working_directory, "Working directory of the program to run", :type => :string
  conflicts :background, :timeout
  conflicts :background, :delay
end

rvc_alias :start_program
rvc_alias :start_program, :exec

def start_program vm, opts
  guestOperationsManager = vm._connection.serviceContent.guestOperationsManager
  err "This command requires vSphere 5 or greater" unless guestOperationsManager.respond_to? :processManager
  processManager = guestOperationsManager.processManager

  auth = authenticate opts

  pid = processManager.
    StartProgramInGuest(
      :vm => vm,
      :auth => auth,
      :spec => VIM.GuestProgramSpec(
        :arguments => opts[:arguments],
        :programPath => opts[:program_path],
        :envVariables => opts[:env],
        :workingDirectory => opts[:working_directory]
      )
    )

  Timeout.timeout opts[:timeout] do
    while true
      processes = processManager.
        ListProcessesInGuest(
          :vm => vm,
          :auth => auth,
          :pids => [pid]
        )
      process = processes.first

      if !process.endTime.nil?
        if process.exitCode != 0
          err "Process failed with exit code #{process.exitCode}"
        end
        break
      elsif opts[:background]
        break
      end

      sleep opts[:delay]
    end
  end
rescue Timeout::Error
  err "Timed out waiting for process to finish."
end
