include RLUI::Util

VMRC = ENV['VMRC'] || search_path('vmrc')

def view *paths
  err "VMRC not found" unless VMRC
  paths.each do |path|
    obj = lookup path
    expect obj, VIM::VirtualMachine
    moref = obj._ref
    fork do
      ENV['https_proxy'] = ENV['HTTPS_PROXY'] = ''
      $stderr.reopen("#{ENV['HOME']||'.'}/.rlui-vmrc.log", "w")
      Process.setpgrp
      exec VMRC, '-M', moref, '-h', $opts[:host], '-u', $opts[:user], '-p', $opts[:password], '--disable-ssl-checking'
    end
  end
end
