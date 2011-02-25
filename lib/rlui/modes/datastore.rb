module RLUI

class DatastoreMode < Mode
  def initialize *args
    super
    aliases.merge!(
      'info' => 'datastore.info',
      'i' => 'datastore.info',
    )
  end
end

end
