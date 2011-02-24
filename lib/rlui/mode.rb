module RLUI

class Mode
  attr_reader :display_path, :items, :root, :cur, :aliases

  def initialize root
    @root = root
    @cur = root
    @items = {}
    @next_item_index = 0
    @aliases = {
      'type' => 'basic.type',
      'debug' => 'basic.debug',
      'rc' => 'basic.rc',
      'reload' => 'basic.reload',
      'cd' => 'basic.cd',
      'ls' => 'basic.ls',
    }
  end

  def display_path
    @cached_display_path ||= @cur.pretty_path
  end

  def cd els, relative
    new_cur = relative ? @cur : @root
    els.each do |el|
      if el == '..'
        new_cur = new_cur.parent unless new_cur == @root
      else
        new_cur = new_cur.find(el, VIM::Folder) or fail("no such folder")
      end
    end
    @cached_display_path = nil unless @cur == new_cur
    @cur = new_cur
  end

  def _ls propHash
    propSet = propHash.map { |k,v| { :type => k, :pathSet => v } }
    filterSpec = VIM.PropertyFilterSpec(
      :objectSet => [
        :obj => @cur,
        :skip => true,
        :selectSet => [
          VIM.TraversalSpec(
            :name => 'tsFolder',
            :type => 'Folder',
            :path => 'childEntity',
            :skip => false
          )
        ]
      ],
      :propSet => propSet
    )

    $vim.propertyCollector.RetrieveProperties(:specSet => [filterSpec])
  end

  def clear_items
    @items.clear
    @next_item_index = 0
  end

  def add_item name, obj
    i = @next_item_index
    @next_item_index += 1
    @items[i] = obj
    @items[name] = obj
    i
  end

  def ls
    clear_items
    _ls(:ManagedEntity => %w(name)).each do |r|
      i = add_item r['name'], r.obj
      case r.obj
      when VIM::Folder
        puts "#{i} #{r['name']}/"
      else
        puts "#{i} #{r['name']}"
      end
    end
  end
end

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
