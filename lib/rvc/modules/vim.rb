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
  opt :insecure, "don't verify ssl certificate", :short => 'k', :default => (ENV['RBVMOMI_INSECURE'] == '1')
end

def connect uri, opts
  match = URI_REGEX.match uri
  Trollop.die "invalid hostname" unless match

  username = match[1] || ENV['RBVMOMI_USER']
  password = match[2] || ENV['RBVMOMI_PASSWORD']
  host = match[3]
  path = match[4]
  insecure = opts[:insecure]

  vim = nil
  loop do
    begin
      vim = RbVmomi::VIM.new :host => host,
                              :port => 443,
                              :path => '/sdk',
                              :ns => 'urn:vim25',
                              :rev => '4.0',
                              :ssl => true,
                              :insecure => insecure
      break
    rescue OpenSSL::SSL::SSLError
      err "Connection failed" unless prompt_insecure
      insecure = true
    rescue Errno::EHOSTUNREACH, SocketError
      err $!.message
    end
  end

  # negotiate API version
  rev = vim.serviceContent.about.apiVersion
  vim.rev = [rev, '4.1'].min
  isVC = vim.serviceContent.about.apiType == "VirtualCenter"

  # authenticate
  username = isVC ? 'Administrator' : 'root' unless username
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
      vim.serviceInstance.RetrieveServiceContent
    end
  end

  # XXX remove
  vim.define_singleton_method(:_auth) { { :host => host, :username => username, :password => password } }

  conn_name = host.dup
  conn_name = "#{conn_name}:1" if $connections.member? conn_name
  conn_name.succ! while $connections.member? conn_name

  $connections[conn_name] = vim
end

def prompt_password
  system "stty -echo"
  $stdout.write "password: "
  $stdout.flush
  begin
    ($stdin.gets||exit(1)).chomp
  ensure
    system "stty echo"
    puts
  end
end

def prompt_insecure
  answer = Readline.readline "SSL certificate verification failed. Connect anyway? (y/n) "
  answer == 'yes' or answer == 'y'
end

