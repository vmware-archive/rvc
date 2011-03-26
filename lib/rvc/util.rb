# Copyright (c) 2011 VMware, Inc.  All Rights Reserved.
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

module RVC
module Util
  extend self

  def lookup path
    $shell.fs.lookup path
  end

  def lookup! path, type
    lookup(path).tap do |obj|
      err "Not found: #{path.inspect}" unless obj
      err "Expected #{type} but got #{obj.class} at #{path.inspect}" unless obj.is_a? type
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

  def single_connection objs
    conns = objs.map { |x| x._connection rescue nil }.compact.uniq
    err "No connections" if conns.size == 0
    err "Objects span multiple connections" if conns.size > 1
    conns[0]
  end

  def tasks objs, sym, args={}
    progress(objs.map { |obj| obj._call :"#{sym}_Task", args })
  end

  def progress tasks
    interested = %w(info.progress info.state info.entityName info.error info.name)
    connection = single_connection tasks
    connection.serviceInstance.wait_for_multiple_tasks interested, tasks do |h|
      if interactive?
        h.each do |task,props|
          state, entityName, name = props['info.state'], props['info.entityName'], props['info.name']
          name = $` if name =~ /_Task$/
          if state == 'running'
            text = "#{name} #{entityName}: #{state} "
            progress = props['info.progress']
            barlen = terminal_columns - text.size - 2
            progresslen = ((progress||0)*barlen)/100
            progress_bar = "[#{'=' * progresslen}#{' ' * (barlen-progresslen)}]"
            $stdout.write "\e[K#{text}#{progress_bar}\n"
          elsif state == 'error'
            error = props['info.error']
            $stdout.write "\e[K#{name} #{entityName}: #{error.fault.class.wsdl_name}: #{error.localizedMessage}\n"
          else
            $stdout.write "\e[K#{name} #{entityName}: #{state}\n"
          end
        end
        $stdout.write "\e[#{h.size}A"
        $stdout.flush
      end
    end
    $stdout.write "\e[#{tasks.size}B" if interactive?
    true
  end

  def terminal_columns
    begin
      require 'curses'
      Curses.cols
    rescue LoadError
      80
    end
  end

  def interactive?
    terminal_columns > 0
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

    results = obj._connection.propertyCollector.RetrieveProperties(:specSet => [spec])

    Hash[results.map { |r| [r['name'], r.obj] }]
  end
end
end
