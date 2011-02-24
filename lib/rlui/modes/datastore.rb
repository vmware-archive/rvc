module RLUI

class DatastoreMode < Mode
  def initialize *args
    super
    aliases.merge!(
      'info' => 'datastore.info',
      'i' => 'datastore.info',
    )
  end

  def ls
    clear_items
    _ls(:Folder => %w(name), :Datastore => %w(name summary.capacity summary.freeSpace)).each do |r|
      i = add_item r['name'], r.obj
      case r.obj
      when VIM::Folder
        puts "#{i} #{r['name']}/"
      when VIM::Datastore
        pct_used = 100*(1-(r['summary.freeSpace'].to_f/r['summary.capacity']))
        pct_used_text = "%0.1f%%" % pct_used
        capacity_text = "%0.2fGB" % (r['summary.capacity'].to_f/10**9)
        puts "#{i} #{r['name']} #{capacity_text} #{pct_used_text}"
      else
        puts "#{i} #{r['name']}"
      end
    end
  end
end

end
