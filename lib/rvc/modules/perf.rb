begin
  require 'gnuplot'
  RVC::HAVE_GNUPLOT = true
rescue LoadError
  RVC::HAVE_GNUPLOT = false
end

TIMEFMT = '%Y-%m-%d.%H:%M:%S'
INTERVALS = {
  'realtime' => 20,
  'day' => 300,
  'week' => 1800,
  'month' => 7200,
}
DISPLAY_TIMEFMT = {
  'realtime' => '%H:%M',
  'day' => '%H:%M',
  'week' => '%m/%d',
  'month' => '%Y/%m/%d'
}

opts :plot do
  summary "Plot a graph of the given performance counters"
  arg :obj, "", :lookup => VIM::ManagedEntity
  arg :counter, "Counter name"
  opt :terminal, "Display plot on terminal"
  opt :scale, INTERVALS.keys*'/', :default => 'realtime'
end

def plot obj, counter_name, opts
  err "gnuplot and/or the gnuplot gem are not installed" unless RVC::HAVE_GNUPLOT
  pm = obj._connection.serviceContent.perfManager
  group_key, counter_key, rollup_type = counter_name.split('.', 3)

  all_counters = Hash[pm.perfCounter.map { |x| [x.key, x] }]

  interval_id = INTERVALS[opts[:scale]]
  start_time = (Time.now-interval_id*10).to_datetime

  metrics = pm.QueryAvailablePerfMetric(
    :entity => obj,
    :intervalId => interval_id,
    :startTime => start_time)

  metric = metrics.find do |metric|
    counter = all_counters[metric.counterId]
    counter.groupInfo.key == group_key &&
      counter.nameInfo.key == counter_key &&
      counter.rollupType == rollup_type
  end or err "no such metric"
  counter = all_counters[metric.counterId]

  spec = {
    :entity => obj,
    :metricId => [metric],
    :intervalId => interval_id,
    #:startTime => start_time
  }
  result = pm.QueryPerf(querySpec: [spec])[0]
  times = result.sampleInfo.map(&:timestamp).map { |x| x.strftime TIMEFMT }
  data = result.value[0].value

  if counter.unitInfo.key == 'percent'
    data.map! { |x| x/100 }
  end

  Gnuplot.open do |gp|
    Gnuplot::Plot.new( gp ) do |plot|
      plot.title  "#{counter_name} on #{obj.name}"
      plot.ylabel counter.unitInfo.label
      plot.xlabel "Date"
      plot.terminal 'dumb' if opts[:terminal]

      plot.set 'xdata', 'time'
      plot.set 'format', "x '#{DISPLAY_TIMEFMT[opts[:scale]]}'"
      plot.set 'timefmt', TIMEFMT.inspect

      plot.data << Gnuplot::DataSet.new([times, data]) do |ds|
        ds.with = "lines"
        ds.using = '1:2'
        ds.notitle
      end

      #puts plot.to_gplot
    end
  end
end


# TODO fix flickering
opts :watch do
  summary "Watch a graph of the given performance counters"
  arg :obj, "", :lookup => VIM::ManagedEntity
  arg :counter, "Counter name"
end

def watch obj, counter_name
  while true
    plot obj, counter_name, :terminal => true, :scale => 'realtime'
    sleep 5
    n = 25
    $stdout.write "\e[#{n}A"
    n.times do |i|
      $stdout.write "\e[K\n"
    end
    $stdout.write "\e[#{n}A"
  end
rescue Interrupt
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
