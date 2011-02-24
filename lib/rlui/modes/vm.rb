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

  def ls
    clear_items
    _ls(:Folder => %w(name), :VirtualMachine => %w(name runtime.powerState)).each do |r|
      i = add_item r['name'], r.obj
      case r.obj
      when VIM::Folder
        puts "#{i} #{r['name']}/"
      when VIM::VirtualMachine
        puts "#{i} #{r['name']} #{r['runtime.powerState']}"
      else
        puts "#{i} #{r['name']}"
      end
    end
  end
end

end
