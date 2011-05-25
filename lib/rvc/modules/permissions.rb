opts :get do
  summary "Display the permissions of a managed entity"
  arg :obj, nil, :lookup => VIM::ManagedEntity, :multi => true
end

def get objs
  conn = single_connection objs
  authMgr = conn.serviceContent.authorizationManager
  roles = Hash[authMgr.roleList.map { |x| [x.roleId, x] }]
  objs.each do |obj|
    puts "#{obj.name}:"
    perms = authMgr.RetrieveEntityPermissions(:entity => obj, :inherited => true)
    perms.each do |perm|
      puts " #{perm[:principal]} (#{perm[:group] ? 'group' : 'user'}): #{roles[perm[:roleId]].name}"
    end
  end
end


opts :set do
  summary "Set the permissions on a managed entity"
  arg :obj, nil, :lookup => VIM::ManagedEntity, :multi => true
  opt :role, "Role", :type => :string, :required => true
  opt :principal, "Principal", :type => :string, :required => true
  opt :group, "Does the principal refer to a group?"
  opt :propagate, "Propagate?"
end

def set objs, opts
  conn = single_connection objs
  authMgr = conn.serviceContent.authorizationManager
  role = authMgr.roleList.find { |x| x.name == opts[:role] }
  err "no such role #{role.inspect}" unless role
  perm = { :roleId => role.roleId,
           :principal => opts[:principal],
           :group => opts[:group],
           :propagate => opts[:propagate] }
  objs.each do |obj|
    authMgr.SetEntityPermissions(:entity => obj, :permission => [perm])
  end
end
