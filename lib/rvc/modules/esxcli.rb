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

require 'rvc/vim'

require 'rvc/ttl_cache'

raw_opts :execute, "Execute an esxcli command"

EsxcliCache = RVC::TTLCache.new 60

def lookup_esxcli host, args
  cur = EsxcliCache[host, :esxcli]
  i = 0
  while i < args.length
    k = args[i]
    if cur.namespaces.member? k
      cur = cur.namespaces[k]
    elsif cur.commands.member? k
      cur = cur.commands[k]
      break
    else
      err "nonexistent esxcli namespace or command #{k.inspect}"
    end
    i += 1
  end
  return cur
end

rvc_completor :execute do |word, args|
  if args.length == 1
    # HostSystem argument
    shell.completion.fs_candidates word
  else
    # esxcli namespace/method/arguments
    host = lookup_single! args[0], VIM::HostSystem
    o = lookup_esxcli host, args[1...-1]

    case o
    when VIM::EsxcliCommand
      parser = o.option_parser
      candidates = parser.specs.map { |k,v| "--#{v[:long]}" }.sort
    when VIM::EsxcliNamespace
      candidates = o.namespaces.keys + o.commands.keys
    else
      fail "unreachable"
    end

    candidates.grep(/^#{Regexp.escape word}/).
               map { |x| [x, ' '] }
  end
end

def execute *args
  host_path = args.shift or err "host argument required"
  host = lookup_single! host_path, VIM::HostSystem
  o = lookup_esxcli host, args

  case o
  when VIM::EsxcliCommand
    cmd = o
    parser = cmd.option_parser
    begin
      opts = parser.parse args
    rescue Trollop::CommandlineError
      err "error: #{$!.message}"
    rescue Trollop::HelpNeeded
      parser.educate
      return
    end
    begin
      opts.reject! { |k,v| !opts.member? :"#{k}_given" }
      result = cmd.call(opts)
    rescue RbVmomi::Fault
      puts "#{$!.message}"
      puts "cause: #{$!.faultCause}" if $!.respond_to? :faultCause and $!.faultCause
      $!.faultMessage.each { |x| puts x } if $!.respond_to? :faultMessage
      $!.errMsg.each { |x| puts "error: #{x}" } if $!.respond_to? :errMsg
    end
    output_formatted cmd, result
  when VIM::EsxcliNamespace
    ns = o
    unless ns.commands.empty?
      puts "Available commands:"
      ns.commands.each do |k,v|
        puts "#{k}: #{v.cli_info.help}"
      end
      puts unless ns.namespaces.empty?
    end
    unless ns.namespaces.empty?
      puts "Available namespaces:"
      ns.namespaces.each do |k,v|
        puts "#{k}: #{v.cli_info.help}"
      end
    end
  end
end

rvc_alias :execute, :esxcli
rvc_alias :execute, :x

def output_formatted cmd, result
  hints = Hash[cmd.cli_info.hints]
  formatter = hints['formatter']
  formatter = "none" if formatter == ""
  sym = :"output_formatted_#{formatter}"
  if respond_to? sym
    send sym, result, cmd.cli_info, hints
  else
    puts "Unknown formatter #{formatter.inspect}"
    pp result
  end
end

def output_formatted_none result, info, hints
  pp result if result != true
end

def output_formatted_simple result, info, hints
  case result
  when Array
    result.each do |r|
      output_formatted_simple r, info, hints
      puts
    end
  when RbVmomi::BasicTypes::DataObject
    prop_descs = result.class.ancestors.
                        take_while { |x| x != RbVmomi::BasicTypes::DataObject &&
                                         x != VIM::DynamicData }.
                        map(&:props_desc).flatten(1)
    prop_descs.each do |desc|
      print "#{desc['name']}: "
      pp result.send desc['name']
    end
  else
    pp result
  end
end

def table_key str
  str.downcase.gsub(/[^\w\d_]/, '')
end

def output_formatted_table result, info, hints
  if result.empty?
    puts "Empty result"
    return
  end

  columns =
    if hints.member? 'table-columns'
      hints['table-columns'].split ','
    elsif k = hints.keys.find { |k| k =~ /^fields:/ }
      hints[k].split ','
    else []
    end
  ordering = columns.map { |x| table_key x }

  units = Hash[hints.select { |k,v| k =~ /^units:/ }.map { |k,v| [table_key(k.match(/[^.]+$/).to_s), v] }]

  table = Terminal::Table.new :headings => columns
  result.each do |r|
    row = []
    r.class.full_props_desc.each do |desc|
      name = desc['name']
      key = table_key name
      next unless idx = ordering.index(key)
      val = r.send name
      unit = units[key]
      row[idx] =
        case unit
        when nil then val
        when '%' then "#{val}#{unit}"
        else "#{val} #{unit}"
        end
    end
    table.add_row row
  end
  puts table
end
