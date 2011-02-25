module RLUI

class NetworkMode < Mode
  def initialize *args
    super
    aliases.merge!(
      'info' => 'network.info',
      'i' => 'network.info',
    )
  end
end

end
