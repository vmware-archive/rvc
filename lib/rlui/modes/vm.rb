module RLUI

class VmMode < Mode
  def initialize *args
    super
    aliases.merge!(
      'on' => 'vm.on',
      'off' => 'vm.off',
      'reset' => 'vm.reset',
      'r' => 'vm.reset',
      'suspend' => 'vm.suspend',
      's' => 'vm.suspend',
      'info' => 'vm.info',
      'i' => 'vm.info',
      'kill' => 'vm.kill',
      'k' => 'vm.kill',
      'ping' => 'vm.ping',
      'view' => 'vmrc.view',
      'v' => 'vmrc.view',
      'V' => 'vnc.view',
      'ssh' => 'vm.ssh'
    )
  end
end

end
