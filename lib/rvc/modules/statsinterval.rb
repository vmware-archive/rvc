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

#see vSphere Client: Administration -> vCenter Server Settings -> Statistics -> Statistics Intervals

def stats_time secs
  length = secs / 60

  [[60, "Minutes"], [24, "Hours"], [7, "Days"], [4, "Weeks"], [12, "Months"]].each do |div, name|
    if length < div
      return "#{length} #{name}"
    end
    length = length / div
  end

  return "#{length} Years"
end


opts :list do
  summary "List intervals for collecting vCenter statistics"
end

def list
  conn = lookup_single('~@')
  pm = conn.serviceContent.perfManager

  table = Terminal::Table.new
  table.add_row ["Name", "Enabled", "Interval Duration", "Save For", "Statistics Level"]
  table.add_separator

  pm.historicalInterval.each do |interval|
    table.add_row [interval.name, interval.enabled, stats_time(interval.samplingPeriod),
                   stats_time(interval.length), interval.level]
  end

  puts table
end


opts :update do
  summary "Update intervals for collecting vCenter statistics"
  arg :name, "Name of the historical interval"
  opt :period, "Number of seconds that data is sampled", :short => 's', :type => :int, :required => false
  opt :length, "Number of seconds that the statistics are saved", :short => 'l', :type => :int, :required => false
  opt :level, "Statistics collection level", :short => 'v', :type => :int, :required => false
  opt :enabled, "Enable or disable the the interval", :short => 'e', :type => :string, :required => false
end

def update name, opts
  conn = single_connection [shell.fs.cur]
  perfman = conn.serviceContent.perfManager

  interval = perfman.historicalInterval.select {|i| i.name == name or i.name == "Past #{name}" }.first
  err "no such interval" unless interval

  interval.samplingPeriod = opts[:period] if opts[:period]
  interval.length = opts[:length] if opts[:length]
  interval.level = opts[:level] if opts[:level]
  
  case opts[:enabled]
  when nil
  when "false"
    interval.enabled = false
  when "true"
    interval.enabled = true
  else
    err "invalid value for enabled option"
  end

  perfman.UpdatePerfInterval(:interval => interval)
end
