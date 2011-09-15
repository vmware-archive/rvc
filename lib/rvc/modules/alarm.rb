opts :show do
  summary "Show alarms on the given entities"
  arg :entity, nil, :lookup => VIM::ManagedEntity, :multi => true
end

IGNORE_STATUSES = %w(green gray)

def show objs
  alarm_states = objs.map(&:triggeredAlarmState).flatten.uniq
  alarm_states.each do |alarm_state|
    info = alarm_state.alarm.info
    colored_alarm_status = status_color alarm_state.overallStatus, alarm_state.overallStatus
    puts "#{alarm_state.entity.name}: #{info.name} (#{colored_alarm_status}): #{info.description}"
  end
end

rvc_alias :show, :alarms
