begin
  require 'gnuplot'
  RVC::HAVE_GNUPLOT = true
rescue LoadError
  RVC::HAVE_GNUPLOT = false
end

TIMEFMT = '%Y-%m-%dT%H:%M:%SZ'

DISPLAY_TIMEFMT = {
  :realtime => '%H:%M',
  1 => '%H:%M',
  2 => '%m/%d',
  3 => '%m/%d',
  4 => '%Y/%m/%d',
}

opts :plot do
  summary "Plot a graph of the given performance counters"
  arg :counter, "Counter name"
  arg :obj, "", :lookup => VIM::ManagedEntity, :multi => true
  opt :terminal, "Display plot on terminal", :default => ENV['DISPLAY'].nil?
  opt :start, "Start time", :type => :date, :short => 's'
  opt :end, "End time", :type => :date, :short => 'e'
end

def plot counter_name, objs, opts
  err "gnuplot and/or the gnuplot gem are not installed" unless RVC::HAVE_GNUPLOT
  vim = single_connection objs
  pm = vim.serviceContent.perfManager
  group_key, counter_key, rollup_type = counter_name.split('.', 3)

  now = Time.now
  opts[:end] ||= now
  opts[:start] ||= opts[:end] - 1800

  err "end time is in the future" unless opts[:end] <= Time.now
  ago = now - opts[:start]

  if ago < 3600
    #puts "Using realtime interval, period = 20 seconds."
    interval_id = 20
    display_timefmt = DISPLAY_TIMEFMT[:realtime]
  else
    intervals = pm.historicalInterval
    interval = intervals.find { |x| now - x.length < opts[:start] }
    err "start time is too long ago" unless interval
    #puts "Using historical interval #{interval.name.inspect}, period = #{interval.samplingPeriod} seconds."
    interval_id = interval.samplingPeriod
    display_timefmt = DISPLAY_TIMEFMT[interval.key]
  end

  all_counters = Hash[pm.perfCounter.map { |x| [x.key, x] }]

  metrics = pm.QueryAvailablePerfMetric(
    :entity => objs.first,
    :interval => interval_id)

  metric = metrics.find do |metric|
    counter = all_counters[metric.counterId]
    counter.groupInfo.key == group_key &&
      counter.nameInfo.key == counter_key &&
      counter.rollupType == rollup_type
  end or err "no such metric"
  counter = all_counters[metric.counterId]

  specs = objs.map do |obj|
    {
      :entity => obj,
      :metricId => [metric],
      :intervalId => interval_id,
      :startTime => opts[:start],
      :endTime => opts[:end],
      :format => 'csv',
    }
  end

  if opts[:io]
    io = opts[:io]
  else
    cmd = Gnuplot.gnuplot(true) or err 'gnuplot not found'
    io = IO::popen(cmd, "w")
  end

  begin
    plot = Gnuplot::Plot.new(io) do |plot|
      if objs.size == 1
        plot.title "#{counter_name} on #{objs[0].name}"
      else
        plot.title counter_name
      end

      plot.ylabel counter.unitInfo.label
      plot.xlabel "Time"
      plot.terminal 'dumb' if opts[:terminal]

      plot.set 'xdata', 'time'
      plot.set 'format', "x '#{display_timefmt}'"
      plot.set 'timefmt', TIMEFMT.inspect

      plot.data = retrieve_datasets pm, counter, specs
    end
    io.puts
  ensure
    io.close unless opts[:io]
  end
end

def retrieve_datasets pm, counter, specs
  results = pm.QueryPerf(querySpec: specs)
  datasets = results.map do |result|
    times = result.sampleInfoCSV.split(',').select { |x| x['T']  }
    data = result.value[0].value.split(',').map(&:to_i)

    if counter.unitInfo.key == 'percent'
      times.length.times do |i|
        times[i] = data[i] = nil if data[i] < 0
      end

      times.compact!
      data.compact!
      data.map! { |x| x/100.0 }
    end

    Gnuplot::DataSet.new([times, data]) do |ds|
      ds.notitle if specs.size == 1
      ds.with = "lines"
      ds.using = '1:2'
      ds.title = result.entity.name
    end
  end
end


opts :watch do
  summary "Watch a graph of the given performance counters"
  arg :counter, "Counter name"
  arg :objs, "", :lookup => VIM::ManagedEntity, :multi => true
  opt :interval, "Seconds between updates", :short => 'i', :default => 10
  opt :terminal, "Display plot on terminal", :default => ENV['DISPLAY'].nil?
end

def watch counter_name, objs, opts
  cmd = Gnuplot.gnuplot(false) or err 'gnuplot not found'
  io = IO::popen(cmd, "w")
  puts "Press Ctrl-C to stop."
  while true
    plot counter_name, objs, :io => io, :terminal => opts[:terminal]
    sleep opts[:interval]
    if opts[:terminal]
      $stdout.write "\e[25A"
      $stdout.flush
    end
  end
rescue Interrupt
ensure
  io.close if io
end


opts :metrics do
  summary "Display available metrics on an object"
  arg :obj, nil, :lookup => VIM::ManagedEntity
end

def metrics obj
  perfmgr = obj._connection.serviceContent.perfManager
  interval = perfmgr.provider_summary(obj).refreshRate
  if interval == -1
    # Object does not support real time stats
    interval = nil
  end
  res = perfmgr.QueryAvailablePerfMetric(
    :entity => obj, 
    :intervalId => interval)
  res.map! { |x| perfmgr.perfcounter_idhash[x.counterId] }.uniq!

  table = Terminal::Table.new
  table.add_row ['Perf metric', 'Description', 'Unit']
  table.add_separator
  res.sort { |a, b| a.pretty_name <=> b.pretty_name }.each do |counter|
    table.add_row([counter.pretty_name, counter.nameInfo.label, counter.unitInfo.label])
  end
  puts table
end

opts :metric do
  summary "Retrieve detailed information about a perf metric"
  arg :obj, nil, :lookup => VIM::ManagedEntity
  arg :metric, nil, :type => :string
end

def metric obj, metric
  perfmgr = obj._connection.serviceContent.perfManager
  interval = perfmgr.provider_summary(obj).refreshRate
  if interval == -1
    # Object does not support real time stats
    interval = nil
  end
  res = perfmgr.QueryAvailablePerfMetric(
    :entity => obj, 
    :intervalId => interval)
  res.select! { |x| perfmgr.perfcounter_idhash[x.counterId].pretty_name == metric }

  metricInfo = perfmgr.perfcounter_hash[metric]
  puts "Metric label: #{metricInfo.nameInfo.label}"
  puts "Metric summary: #{metricInfo.nameInfo.summary}"
  puts "Unit label: #{metricInfo.unitInfo.label}"
  puts "Unit summary: #{metricInfo.unitInfo.label}"
  puts "Rollup type: #{metricInfo.rollupType}"
  puts "Stats type: #{metricInfo.statsType}"
  puts "Real time interval: #{interval || 'N/A'}"

  instances = res.map(&:instance).reject(&:empty?)
  unless instances.empty?
    puts "Instances:"
    instances.map do |x|
      puts "  #{x}"
    end
  end
end

opts :stats do
  summary "Retrieve performance stats for given object"
  arg :metrics, nil, :type => :string
  arg :obj, nil, :multi => true, :lookup => VIM::ManagedEntity
  opt :samples, "Number of samples to retrieve", :type => :int
end

def stats metrics, objs, opts
  metrics = metrics.split(",")
  obj = objs.first
  perfmgr = obj._connection.serviceContent.perfManager
  interval = perfmgr.provider_summary(obj).refreshRate
  start_time = nil
  if interval == -1
    # Object does not support real time stats
    interval = 300
    start_time = Time.now - 300 * 5
  end
  stat_opts = {
    :interval => interval,
    :startTime => start_time,
  }
  stat_opts[:max_samples] = opts[:samples] if opts[:samples]
  res = perfmgr.retrieve_stats objs, metrics, stat_opts

  table = Terminal::Table.new
  table.add_row ['Object', 'Metric', 'Values', 'Unit']
  table.add_separator
  objs.each do |obj|
    metrics.each do |metric|
      stat = res[obj][:metrics][metric]
      metric_info = perfmgr.perfcounter_hash[metric]
      table.add_row([obj.name, metric, stat.join(','), metric_info.unitInfo.label])
    end
  end
  puts table
end
