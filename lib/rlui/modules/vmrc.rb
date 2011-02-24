include RLUI::Util

VMRC = ENV['VMRC'] || search_path('vmrc')

def view *ids
  err "VMRC not found" unless VMRC
  ids.each do |id|
    moref = vm(id)._ref
    fork do
      ENV['https_proxy'] = ENV['HTTPS_PROXY'] = ''
      $stderr.reopen("#{ENV['HOME']||'.'}/.rlui-vmrc.log", "w")
      Process.setpgrp
      exec VMRC, '-M', moref, '-h', $opts[:host], '-u', $opts[:user], '-p', $opts[:password], '--disable-ssl-checking'
    end
  end
end
