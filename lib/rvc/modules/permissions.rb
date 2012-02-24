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
    flags = []
    flags << 'group' if perm[:group]
    flags << 'propagate' if perm[:propagate]
      puts " #{perm[:principal]}#{flags.empty? ? '' : " (#{flags * ', '})"}: #{roles[perm[:roleId]].name}"
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


opts :remove do
  summary "Remove permissions for the given user from a managed entity"
  arg :obj, nil, :lookup => VIM::ManagedEntity, :multi => true
  opt :principal, "Principal", :type => :string, :required => true
  opt :group, "Does the principal refer to a group?"
end

def remove objs, opts
  conn = single_connection objs
  authMgr = conn.serviceContent.authorizationManager
  objs.each do |obj|
    authMgr.RemoveEntityPermission :entity => obj,
                                   :user => opts[:principal],
                                   :isGroup => opts[:group]
  end
end
