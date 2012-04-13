require 'date'

class Time
  def to_datetime
    # Convert seconds + microseconds into a fractional number of seconds
    seconds = sec + Rational(usec, 10**6)

    # Convert a UTC offset measured in minutes to one measured in a
    # fraction of a day.
    offset = Rational(utc_offset, 60 * 60 * 24)
    DateTime.new(year, month, day, hour, min, seconds, offset)
  end
end

RbVmomi::VIM::PerformanceManager
class RbVmomi::VIM::PerformanceManager
  def perfcounter_cached
    @perfcounter ||= perfCounter
  end
  
  def perfcounter_hash
    @perfcounter_hash ||= Hash[perfcounter_cached.map{|x| [x.name, x]}]
  end
  
  def perfcounter_idhash 
    @perfcounter_idhash ||= Hash[perfcounter_cached.map{|x| [x.key, x]}]
  end
  
  def provider_summary obj
    @provider_summary ||= {}
    @provider_summary[obj.class] ||= QueryPerfProviderSummary(:entity => obj)
  end

  def retrieve_stats objects, metrics, opts = {}
    opts = opts.dup
    max_samples = opts[:max_samples] || 1
    realtime = false
    if not opts[:interval]
      provider = provider_summary objects.first
      opts[:interval] = provider.refreshRate
      realtime = true
    else
      provider = provider_summary objects.first
      if opts[:interval] == provider.refreshRate
        realtime = true
      end
    end
    metric_ids = metrics.map do |x| 
      RbVmomi::VIM::PerfMetricId(:counterId => perfcounter_hash[x].key, :instance => '*')
    end
    query_specs = objects.map do |obj|
      RbVmomi::VIM::PerfQuerySpec({
        :maxSample => max_samples, 
        :entity => obj, 
        :metricId => metric_ids, 
        :intervalId => opts[:interval],
        :startTime => (realtime == false ? opts[:start_time].to_datetime : nil),
      })
    end
    stats = QueryPerf(:querySpec => query_specs)
    _result = Hash.new
    stats.map do |res|
      _metrics = Hash.new
      res.value.map do |metric|
        inst_name = metric.id.instance.nil? ? '' : '-'+metric.id.instance
        if inst_name.size.eql?(1)
          inst_name = ''
        end
        name = perfcounter_idhash[metric.id.counterId].name + inst_name
        _metrics[name] = metric.value
      end
      _res = Hash.new
      _res[:metrics] = _metrics
      _res[:sampleInfo] = res.sampleInfo
      _result[res.entity] = _res
    end
    _result
  end

  def active_intervals
    intervals = historicalInterval
    Hash[(1..4).map { |level| [level, intervals.select { |x| x.enabled && x.level >= level }] }]
  end
end
