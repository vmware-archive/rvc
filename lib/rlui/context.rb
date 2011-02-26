module RLUI

class Context
  attr_reader :items, :root, :cur

  def initialize root, initial_mode
    @root = root
    @cur = root
    @items = {}
    @next_item_index = 0
    @path = []
    @mode_stack = [initial_mode]
  end

  def display_path
    @path * '/'
  end

  def mode
    @mode_stack[-1]
  end

  def parse_path path
    els = path.split '/'
    absolute = els[0].nil? || els[0].empty?
    els.shift if absolute
    [els, absolute]
  end

  def lookup path
    case path
    when Integer
      @items[path] or fail("no such item")
    when String
      els, absolute = parse_path path
      base = absolute ? @root : cur
      traverse(base, els) or fail("not found")
    else fail
    end
  end

  def traverse base, els
    els.inject(base) do |cur,el|
      case el
      when '.'
        cur
      when '..'
        cur == @root ? cur : cur.parent
      else
        traverse_one(cur, el) or fail("no such arc #{el}")
      end
    end
  end

  def traverse_one cur, el
    case cur
    when VIM::ManagedEntity
      $vim.searchIndex.FindChild(:entity => cur, :name => el)
    else
      fail "not a container"
    end
  end

  def transition_mode cur, new, mode, el
    case new
    when VIM::Folder
      if cur.is_a? VIM::Datacenter
        case el
        when 'vm' then :vm_folder
        when 'host' then :host_folder
        when 'datastore' then :datastore_folder
        when 'network' then :network_folder
        else fail
        end
      else
        mode
      end
    else
      new.class.wsdl_name.to_sym
    end
  end

  def cd path
    els, absolute = parse_path path
    new_cur = absolute ? @root : @cur
    new_path = absolute ? [] : @path.dup
    new_mode_stack = @mode_stack.dup
    els.each do |el|
      if el == '..'
        new_cur = new_cur.parent unless new_cur == @root
        new_path.pop
        new_mode_stack.pop
      else
        prev = new_cur
        new_cur = traverse_one(new_cur, el) or fail("no such arc #{el}")
        new_mode = transition_mode prev, new_cur, new_mode_stack[-1], el
        new_path.push el
        new_mode_stack.push new_mode
      end
    end
    @cur = new_cur
    @path = new_path
    @mode_stack = new_mode_stack
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

  GLOBAL_ALIASES = {
    'type' => 'basic.type',
    'debug' => 'basic.debug',
    'rc' => 'basic.rc',
    'reload' => 'basic.reload',
    'cd' => 'basic.cd',
    'ls' => 'basic.ls',
  }

  ALIASES = Hash.new { |h,k| h[k] = GLOBAL_ALIASES.dup }

  ALIASES[:datastore_folder].merge!(
    'info' => 'datastore.info',
    'i' => 'datastore.info'
  )

  ALIASES[:computer_folder].merge!(
    'info' => 'computer.info',
    'i' => 'computer.info'
  )

  ALIASES[:network_folder].merge!(
    'info' => 'network.info',
    'i' => 'network.info'
  )

  ALIASES[:vm_folder].merge!(
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

  def aliases
    ALIASES[mode]
  end
end

end
