# Copyright (c) 2013 VMware, Inc.  All Rights Reserved.
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

opts :authenticate do
  summary "Authenticate within guest"
  arg :vm, nil, :lookup => VIM::VirtualMachine, :multi => true
  opt :interactive_session, "Allow command to interact with desktop", :default => false, :type => :bool
  opt :password, "Password in guest", :type => :string
  opt :username, "Username in guest", :default => "root", :type => :string
end

def authenticate vms, opts
  vms.each do |vm|
    auth = ((@auths ||= {})[vm] ||= {})[opts[:username]]
  
    if opts[:password].nil? or opts[:password].empty?
      opts[:password] = ask("password: ") { |q| q.echo = false }
    end
  
    auth = VIM.NamePasswordAuthentication(
      :username => opts[:username],
      :password => opts[:password],
      :interactiveSession => opts[:interactive_session]
    )
  
    @auths[vm][opts[:username]] = auth
    begin
      check_auth vm, opts
    rescue
      clear_auth vm, opts
      err "Could not authenticate: #{$!}"
    end
  end
end


opts :check_auth do
  summary "Check credentials"
  arg :vm, nil, :lookup => VIM::VirtualMachine
  opt :username, "Username in guest", :default => "root", :type => :string
end

def check_auth vm, opts
  auth = get_auth vm, opts

  guestOperationsManager = vm._connection.serviceContent.guestOperationsManager

  err "This command requires vSphere 5 or greater" unless guestOperationsManager.respond_to? :authManager
  guestOperationsManager.authManager.ValidateCredentialsInGuest(
    :vm => vm,
    :auth => auth
  )
end


opts :list_auth do
  summary "List available credentials"
  arg :vm, nil, :lookup => VIM::VirtualMachine, :required => false
end

def list_auth vm
  if @auths.nil?
    puts "No credentials available."
    return
  end

  if vm.nil?
    auth_list = @auths
  elsif !@auths.member? vm
    puts "No credentials available."
    return
  else
    auth_list = { vm => @auths[vm] }
  end

  auth_list.each_key do |vmkey|
    puts vmkey.rvc_path_str
    auth_list[vmkey].each_key do |userkey|
      puts "  #{userkey}"
    end
  end
end


opts :clear_auth do
  summary "Clear credentials"
  arg :vm, nil, :lookup => VIM::VirtualMachine, :required => false
  opt :username, "Username in guest", :default => "root", :type => :string
end

def clear_auth vm, opts
  unless @auths.nil? or vm.nil?
    if @auths.member? vm
      @auths[vm].delete opts[:username]
      @auths.delete vm if @auths[vm].empty?
      @auths = nil if @auths.empty?
    end
  end
end


def get_auth vm, opts
  auth = @auths.fetch(vm).fetch(opts[:username])
ensure
  err "No credentials found. You must authenticate before executing this command." if auth.nil?
end


# File commands
opts :chmod do
  summary "Change file attributes"
  arg :vm, nil, :lookup => VIM::VirtualMachine
  opt :group_id, "Group ID of file", :type => :int
  opt :guest_path, "Path in guest to change ownership of", :required => true, :type => :string
  opt :owner_id, "Owner ID of file", :type => :int
  opt :permissions, "Permissions of file", :type => :string
  opt :username, "Username in guest", :default => "root", :type => :string
end

def chmod vm, opts
  guestOperationsManager = vm._connection.serviceContent.guestOperationsManager
  err "This command requires vSphere 5 or greater" unless guestOperationsManager.respond_to? :fileManager
  fileManager = guestOperationsManager.fileManager

  opts[:permissions] = opts[:permissions].to_i(8) if opts[:permissions]

  auth = get_auth vm, opts

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
  opt :prefix, "Prefix of temporary directory", :required => true, :type => :string
  opt :suffix, "Suffix of temporary directory", :required => true, :type => :string
  opt :username, "Username in guest", :default => "root", :type => :string
end

def mktmpdir vm, opts
  guestOperationsManager = vm._connection.serviceContent.guestOperationsManager
  err "This command requires vSphere 5 or greater" unless guestOperationsManager.respond_to? :fileManager
  fileManager = guestOperationsManager.fileManager

  auth = get_auth vm, opts

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
  opt :prefix, "Prefix of temporary directory", :required => true, :type => :string
  opt :suffix, "Suffix of temporary directory", :required => true, :type => :string
  opt :username, "Username in guest", :default => "root", :type => :string
end

def mktmpfile vm, opts
  guestOperationsManager = vm._connection.serviceContent.guestOperationsManager
  err "This command requires vSphere 5 or greater" unless guestOperationsManager.respond_to? :fileManager
  fileManager = guestOperationsManager.fileManager

  auth = get_auth vm, opts

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
  opt :recursive, "Delete all subdirectories", :default => false, :type => :bool
  opt :username, "Username in guest", :default => "root", :type => :string
end

def rmdir vm, opts
  guestOperationsManager = vm._connection.serviceContent.guestOperationsManager
  err "This command requires vSphere 5 or greater" unless guestOperationsManager.respond_to? :fileManager
  fileManager = guestOperationsManager.fileManager

  auth = get_auth vm, opts

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
  opt :username, "Username in guest", :default => "root", :type => :string
end

def rmfile vm, opts
  guestOperationsManager = vm._connection.serviceContent.guestOperationsManager
  err "This command requires vSphere 5 or greater" unless guestOperationsManager.respond_to? :fileManager
  fileManager = guestOperationsManager.fileManager

  auth = get_auth vm, opts

  fileManager.
    DeleteFileInGuest(
      :vm => vm,
      :auth => auth,
      :filePath => opts[:guest_path]
    )
end

def generic_http_download uri, local_path
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.verify_mode = OpenSSL::SSL::VERIFY_NONE
  #http.set_debug_output $stderr
  http.start

#  headers = { 'cookie' => connection.cookie }
  headers = {}
  http_path = "#{uri.path}?#{uri.query}"
  http.request_get(http_path, headers) do |res|
    case res
    when Net::HTTPOK
      len = res.content_length
      count = 0
      File.open(local_path, 'wb') do |io|
        res.read_body do |segment|
          count += segment.length
          io.write segment
          $stdout.write "\e[0G\e[Kdownloading #{count}/#{len} bytes (#{(count*100)/len}%)"
          $stdout.flush
        end
      end
      $stdout.puts
    else
      err "download failed: #{res.message}"
    end
  end
end
  
def generic_http_upload local_path, uri, size = nil
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.verify_mode = OpenSSL::SSL::VERIFY_NONE
  #http.set_debug_output $stderr
  http.start


  open(local_path, 'rb') do |io|
    stream = ProgressStream.new(io, size || io.stat.size) do |s|
      $stdout.write "\e[0G\e[Kuploading #{s.count}/#{s.len} bytes (#{(s.count*100)/s.len}%)"
      $stdout.flush
    end

    headers = {
      'content-length' => (size || io.stat.size).to_s,
      'Content-Type' => 'application/octet-stream',
    }
    http_path = "#{uri.path}?#{uri.query}"

    request = Net::HTTP::Put.new http_path, headers
    request.body_stream = stream
    res = http.request(request)
    $stdout.puts
    case res
    when Net::HTTPOK
    else
      err "upload failed: #{res.message}"
    end
  end
end

opts :download_file do
  summary "Download file from guest"
  arg :vm, nil, :lookup => VIM::VirtualMachine
  opt :guest_path, "Path in guest to download from", :required => true, :type => :string
  opt :local_path, "Local file to download to", :required => true, :type => :string
  opt :username, "Username in guest", :default => "root", :type => :string
end

def download_file vm, opts
  guestOperationsManager = vm._connection.serviceContent.guestOperationsManager
  err "This command requires vSphere 5 or greater" unless guestOperationsManager.respond_to? :fileManager
  fileManager = guestOperationsManager.fileManager

  auth = get_auth vm, opts

  download_url = fileManager.
    InitiateFileTransferFromGuest(
      :vm => vm,
      :auth => auth,
      :guestFilePath => opts[:guest_path]
    ).url

  download_uri = URI.parse(download_url.gsub /http(s?):\/\/\*:[0-9]*/, "")
  download_path = "#{download_uri.path}?#{download_uri.query}"
  
  generic_http_download download_uri, opts[:local_path]
end


opts :upload_file do
  summary "Upload file to guest"
  arg :vm, nil, :lookup => VIM::VirtualMachine, :multi => true
  opt :group_id, "Group ID of file", :type => :int
  opt :guest_path, "Path in guest to upload to", :required => true, :type => :string
  opt :local_path, "Local file to upload", :required => true, :type => :string
  opt :overwrite, "Overwrite file", :default => false, :type => :bool
  opt :owner_id, "Owner ID of file", :type => :int
  opt :permissions, "Permissions of file", :type => :string
  opt :username, "Username in guest", :default => "root", :type => :string
end

def upload_file vms, opts
  vms.each do |vm|
    guestOperationsManager = vm._connection.serviceContent.guestOperationsManager
    err "This command requires vSphere 5 or greater" unless guestOperationsManager.respond_to? :fileManager
    fileManager = guestOperationsManager.fileManager
  
    opts[:permissions] = opts[:permissions].to_i(8) if opts[:permissions]
  
    auth = get_auth vm, opts
  
    file_size = nil
    if opts[:local_path] =~ /^http:/
      # XXX: Not acceptable for big files
      file_size = open(opts[:local_path], 'rb').read.length
    else
      err "local file does not exist" unless File.exists? opts[:local_path]
      file = File.new(opts[:local_path], 'rb')
      file_size = file.size
    end  
  
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
        :fileSize => file_size,
        :overwrite => opts[:overwrite]
      )
  
    upload_uri = URI.parse(upload_url.gsub /http(s?):\/\/\*:[0-9]*/, "")
    upload_path = "#{upload_uri.path}?#{upload_uri.query}"
  
    generic_http_upload opts[:local_path], upload_uri, file_size
  end
end


opts :ls_guest do
  summary "List files in guest"
  arg :vm, nil, :lookup => VIM::VirtualMachine
  opt :guest_path, "Path in guest to get directory listing", :required => true, :type => :string
  opt :index, "Which to start the list with", :type => :int, :default => nil
  opt :match_pattern, "Filename filter (regular expression)", :type => :string
  opt :max_results, "Maximum number of results", :type => :int, :default => nil
  opt :username, "Username in guest", :default => "root", :type => :string
end

def ls_guest vm, opts
  guestOperationsManager = vm._connection.serviceContent.guestOperationsManager
  err "This command requires vSphere 5 or greater" unless guestOperationsManager.respond_to? :fileManager
  fileManager = guestOperationsManager.fileManager

  auth = get_auth vm, opts

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
  opt :create_parent_directories, "Create parent directories", :default => false, :type => :bool
  opt :username, "Username in guest", :default => "root", :type => :string
end

def mkdir vm, opts
  guestOperationsManager = vm._connection.serviceContent.guestOperationsManager
  err "This command requires vSphere 5 or greater" unless guestOperationsManager.respond_to? :fileManager
  fileManager = guestOperationsManager.fileManager

  auth = get_auth vm, opts

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
  opt :username, "Username in guest", :default => "root", :type => :string
end

def mvdir vm, opts
  guestOperationsManager = vm._connection.serviceContent.guestOperationsManager
  err "This command requires vSphere 5 or greater" unless guestOperationsManager.respond_to? :fileManager
  fileManager = guestOperationsManager.fileManager

  auth = get_auth vm, opts

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
  opt :overwrite, "Overwrite file", :default => true, :type => :bool
  opt :src_guest_path, "Path in guest to move from", :required => true, :type => :string
  opt :username, "Username in guest", :default => "root", :type => :string
end

def mvfile vm, opts
  guestOperationsManager = vm._connection.serviceContent.guestOperationsManager
  err "This command requires vSphere 5 or greater" unless guestOperationsManager.respond_to? :fileManager
  fileManager = guestOperationsManager.fileManager

  auth = get_auth vm, opts

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
  arg :vm, nil, :lookup => VIM::VirtualMachine, :multi => true
  opt :arguments, "Arguments of command", :default => "", :type => :string
  opt :background, "Don't wait for process to finish", :default => false, :type => :bool
  opt :delay, "Interval in seconds", :type => :float, :default => 5.0
  opt :env, "Environment variable(s) to set (e.g. VAR=value)", :multi => true, :type => :string
  opt :program_path, "Path to program in guest", :required => true, :type => :string
  opt :timeout, "Timeout in seconds", :type => :int, :default => nil
  opt :username, "Username in guest", :default => "root", :type => :string
  opt :working_directory, "Working directory of the program to run", :type => :string
  conflicts :background, :timeout
  conflicts :background, :delay
end

def start_program vms, opts
  vms.each do |vm|
    guestOperationsManager = vm._connection.serviceContent.guestOperationsManager
    err "This command requires vSphere 5 or greater" unless guestOperationsManager.respond_to? :processManager
    processManager = guestOperationsManager.processManager
  
    auth = get_auth vm, opts
  
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
  
    begin
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
  end
end
