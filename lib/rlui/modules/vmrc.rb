include RLUI::Util

VMRC = ENV['VMRC'] || search_path('vmrc')

def view *ids
  err "VMRC not found" unless VMRC
  ids.each do |id|
    cmd = [VMRC, '-M', vm(id)._ref, '-h', $opts[:host], '-u', $opts[:user], '-p', $opts[:password], '--disable-ssl-checking']
    env = ENV.reject { |k,v| k =~ /https_proxy/i }
    spawn env, *cmd, pgroup: true, err: "#{ENV['HOME']||'.'}/.rlui-vmrc.log"
  end
end
