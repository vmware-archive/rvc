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
  def _perfCounter
    @perfCounter ||= perfCounter
  end
  
  def _perfCountersHash
    perfCounterInfoList = _perfCounter
    Hash[perfCounterInfoList.map{|x| ["#{x.groupInfo.key}.#{x.nameInfo.key}.#{x.rollupType}", x]}] 
  end

  def perfCountersHash
    @perfCountersHash ||= _perfCountersHash
  end
  
  def _perfCounterIdToInfo
    perfCounterInfoList = _perfCounter
    Hash[perfCounterInfoList.map{|x| [x.key, {:name => "#{x.groupInfo.key}.#{x.nameInfo.key}.#{x.rollupType}", :details => x}]}] 
  end
  
  def perfCounterIdToInfo 
    @perfCounterIdToInfo ||= _perfCounterIdToInfo
  end
  
  def perfProviderSummary obj
    @perfProviderSummary ||= {}
    @perfProviderSummary[obj.class] ||= QueryPerfProviderSummary(:entity => obj); 
  end

  def retrieve_stats objects, metrics, opts = {}
    maxSamples = opts[:maxSamples] || 1
    realTime = false
    
    if not opts[:interval]
      provider = perfProviderSummary objects.first
      opts[:interval] = provider.refreshRate
      realTime = true
    end
    
    perfMetricIds = metrics.map do |x| 
      RbVmomi::VIM::PerfMetricId(:counterId => perfCountersHash[x].key, :instance => '*')
    end
    
    querySpecs = objects.map do |obj|
      RbVmomi::VIM::PerfQuerySpec({
        :maxSample => maxSamples, 
        :entity => obj, 
        :metricId => perfMetricIds, 
        :intervalId => opts[:interval],
        :startTime => (!realTime ? opts[:startTime].to_datetime : nil),
      })
    end
    stats = QueryPerf(:querySpec => querySpecs)
    
    Hash[stats.map do |res|
      [
        res.entity, 
        {
          :sampleInfo => res.sampleInfo,
          :metrics => Hash[res.value.map do |metric|
            [perfCounterIdToInfo[metric.id.counterId][:name], metric.value]
          end]
        }
      ]
    end]
  end

end