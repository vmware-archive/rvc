module RVC
module Util
  extend self

  def lookup path
    $context.lookup path
  end

  def expect obj, *types
    unless types.any? { |x| obj.is_a? x }
      err "unexpected #{obj.class}"
    end
  end

  def menu items
    items.each_with_index { |x, i| puts "#{i} #{x}" }
    input = Readline.readline("? ", false)
    return if !input or input.empty?
    items[input.to_i]
  end

  def display_inventory tree, folder, indent=0, &b
    tree[folder].sort_by { |k,(o,h)| o._ref }.each do |k,(o,h)|
      case o
      when VIM::Folder
        puts "#{"  "*indent}--#{k}"
        display_inventory tree, o, (indent+1), &b
      else
        b[o,h,indent]
      end
    end
  end

  def search_path bin
    ENV['PATH'].split(':').each do |x|
      path = File.join(x, bin)
      return path if File.exists? path
    end
    nil
  end

  UserError = Class.new(Exception)
  def err msg
    raise UserError.new(msg)
  end

  def progress paths, sym, args={}
    objs = paths.map { |x| lookup(x) }
    tasks = objs.map { |obj| obj._call :"#{sym}_Task", args }

    interested = %w(info.progress info.state info.entityName info.error)

    $vim.serviceInstance.wait_for_multiple_tasks interested, tasks do |h|
      if interactive?
        h.each do |task,props|
          state, entityName = props['info.state'], props['info.entityName']
          if state == 'running'
            text = "#{sym} #{entityName}: #{state} "
            progress = props['info.progress']
            barlen = Curses.cols - text.size - 2
            progresslen = ((progress||0)*barlen)/100
            progress_bar = "[#{'=' * progresslen}#{' ' * (barlen-progresslen)}]"
            $stdout.write "\e[K#{text}#{progress_bar}\n"
          elsif state == 'error'
            error = props['info.error']
            $stdout.write "\e[K#{sym} #{entityName}: #{error.fault.class.wsdl_name}: #{error.localizedMessage}\n"
          else
            $stdout.write "\e[K#{sym} #{entityName}: #{state}\n"
          end
        end
        $stdout.write "\e[#{h.size}A"
        $stdout.flush
      end
    end
    $stdout.write "\e[#{paths.size}B" if interactive?
    true
  end

  def interactive?
    Curses.cols > 0
  end

  def tcsetpgrp pgrp=Process.getpgrp
    return unless $stdin.tty?
    trap('TTOU', 'SIG_IGN')
    $stdin.ioctl 0x5410, [pgrp].pack('I')
    trap('TTOU', 'SIG_DFL')
  end

  def system_fg cmd, env={}
    pid = fork do
      env.each { |k,v| ENV[k] = v }
      Process.setpgrp
      tcsetpgrp
      exec cmd
    end
    Process.waitpid2 pid
    tcsetpgrp
    nil
  end

  def collect_children obj, path
    spec = {
      :objectSet => [
        {
          :obj => obj,
          :skip => true,
          :selectSet => [
            RbVmomi::VIM::TraversalSpec(
              :path => path,
              :type => obj.class.wsdl_name
            )
          ]
        }
      ],
      :propSet => [
        {
          :type => 'ManagedEntity',
          :pathSet => %w(name),
        }
      ]
    }

    results = $vim.propertyCollector.RetrieveProperties(:specSet => [spec])

    Hash[results.map { |r| [r['name'], r.obj] }]
  end
end
end
