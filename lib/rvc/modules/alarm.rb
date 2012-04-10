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
