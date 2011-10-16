require 'fileutils'

class Spinner
  def initialize
    @i = 0
    @spinners = '-\|/-\|/'
  end
  
  def spin
    if $stdout.tty?
      @i += 1
      @i = 0 if @i >= @spinners.length
      $stdout.write "\b#{@spinners[@i..@i]}"
      $stdout.flush
    end
  end
  
  def done
    if $stdout.tty?
      puts "\b- done"
    end
  end

  def abort
    if $stdout.tty?
      puts "\b"
    end
  end
  
  def begin text
    if $stdout.tty?
      $stdout.write "#{Time.now}: #{text} -"
      $stdout.flush
    else
      puts "#{Time.now}: #{text}"
    end
  end
end

RbVmomi::VIM::VirtualMachine
class RbVmomi::VIM::VirtualMachine
  def downloadAsOvf destinationDir, h = {}
    spinner = h[:spinner]
    vmName = self.name
    destinationDir = File.join(destinationDir, vmName)
    FileUtils.mkdir_p destinationDir
    lease = self.ExportVm
    while !['done', 'error', 'ready'].member?(lease.state)
      sleep 1
    end
    if lease.state == "error"
      raise lease.error
    end
    leaseInfo = lease.info

    progress = 5
    keepAliveThread = Thread.new do
      while progress < 100
        lease.HttpNfcLeaseProgress(:percent => progress)
        lastKeepAlive = Time.now
        while progress < 100 && (Time.now - lastKeepAlive).to_i < (leaseInfo.leaseTimeout / 2)
          sleep 1
        end
      end
    end
    
    ovfFiles = leaseInfo.deviceUrl.map do |x| 
      uri = URI.parse(x.url)
      http = Net::HTTP.new(uri.host, uri.port)
      if uri.scheme == 'https'
        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      end
      headers = {'cookie' => _connection.cookie}
      localFilename = File.join(destinationDir, x.targetId)
      spinner.begin "Downloading disk to #{localFilename}" if spinner
      s = 0
      File.open(localFilename, 'w') do |fileIO|
        http.get(uri.path, headers) do |bodySegment|
          fileIO.write bodySegment 
          s += bodySegment.length;
          #$stdout.write "."
          #$stdout.flush 
          spinner.spin if spinner
        end
      end
      
      spinner.done if spinner
      progress += 90 / leaseInfo.deviceUrl.length
      
      {:size => s, :deviceId => x.key, :path => x.targetId}
    end
    puts if spinner
    
    progress = 100
    keepAliveThread.join
    lease.HttpNfcLeaseComplete()
    
    ovfMgr = self._connection.serviceContent.ovfManager
    descriptor = ovfMgr.CreateDescriptor(
      :obj => self, 
      :cdp => {:ovfFiles => ovfFiles}
    )
    File.open(File.join(destinationDir, "#{vmName}.ovf"), 'w') do |io|
      io.write descriptor.ovfDescriptor
    end
  end
end

opts :download do
  summary "Download VM in OVF format"
  arg :destination, nil, :type => :string
  arg :vms, nil, :lookup => VIM::VirtualMachine, :multi => true
end

def download destination, vms
  spinner = Spinner.new
  vms.each do |vm|
    vm.downloadAsOvf destination, :spinner => spinner 
  end
end
