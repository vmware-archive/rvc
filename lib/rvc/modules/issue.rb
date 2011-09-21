opts :show do
  summary "Show issues on the given entities"
  arg :entity, nil, :lookup => VIM::ManagedEntity, :multi => true
end

def show objs
  issues = objs.map(&:configIssue).flatten.uniq
  issues.each do |issue|
    puts issue.fullFormattedMessage
  end
end

rvc_alias :show, :issues
