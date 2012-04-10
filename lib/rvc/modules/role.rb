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

def cur_auth_mgr
  conn = shell.fs.cur._connection
  conn.serviceContent.authorizationManager
end

opts :list do
  summary "List roles in the system"
end

def list
  cur_auth_mgr.roleList.each do |role|
    puts "#{role.name}: #{role.info.summary}"
  end
end


opts :get do
  summary "Display information about a role"
  arg :role, "Role", :type => :string
end

def get name
  role = cur_auth_mgr.roleList.find { |x| x.name == name }
  err "no such role #{name.inspect}" unless role
  puts "label: #{role.info.label}"
  puts "summary: #{role.info.summary}"
  puts "privileges: #{role.privilege.sort * ' '}"
end


opts :permissions do
  summary "List permissions given to this role"
  arg :role, "Role", :type => :string
end

def permissions name
  role = cur_auth_mgr.roleList.find { |x| x.name == name }
  err "no such role #{name.inspect}" unless role
  cur_auth_mgr.RetrieveRolePermissions(:roleId => role.roleId).each do |perm|
    flags = []
    flags << 'group' if perm[:group]
    flags << 'propagate' if perm[:propagate]
    puts " #{perm[:principal]}#{flags.empty? ? '' : " (#{flags * ', '})"}: #{perm.entity.name}"
  end
end


opts :create do
  summary "Create a new role"
  arg :name, "Name of the role", :type => :string
  arg :privilege, "Privileges to assign", :type => :string, :multi => true, :required => false
end

def create name, privileges
  cur_auth_mgr.AddAuthorizationRole :name => name, :privIds => privileges
end


opts :delete do
  summary "Delete a role"
  arg :name, "Name of the role", :type => :string
  opt :force, "Don't fail if the role is in use"
end

def delete name, opts
  role = cur_auth_mgr.roleList.find { |x| x.name == name }
  err "no such role #{name.inspect}" unless role
  cur_auth_mgr.RemoveAuthorizationRole :roleId => role.roleId, :failIfUsed => opts[:force]
end


opts :rename do
  summary "Rename a role"
  arg :old, "Old name", :type => :string
  arg :new, "New name", :type => :string
end

def rename old, new
  role = cur_auth_mgr.roleList.find { |x| x.name == old }
  err "no such role #{old.inspect}" unless role
  cur_auth_mgr.UpdateAuthorizationRole :roleId => role.roleId,
                                       :newName => new,
                                       :privIds => role.privilege
end


opts :add_privilege do
  summary "Add privileges to a role"
  arg :name, "Role name", :type => :string
  arg :privileges, "Privileges", :type => :string, :multi => true
end

def add_privilege name, privileges
  role = cur_auth_mgr.roleList.find { |x| x.name == name }
  err "no such role #{name.inspect}" unless role
  cur_auth_mgr.UpdateAuthorizationRole :roleId => role.roleId,
                                       :newName => role.name,
                                       :privIds => (role.privilege | privileges)

end


opts :remove_privilege do
  summary "Remove privileges from a role"
  arg :name, "Role name", :type => :string
  arg :privileges, "Privileges", :type => :string, :multi => true
end

def remove_privilege name, privileges
  role = cur_auth_mgr.roleList.find { |x| x.name == name }
  err "no such role #{name.inspect}" unless role
  cur_auth_mgr.UpdateAuthorizationRole :roleId => role.roleId,
                                       :newName => role.name,
                                       :privIds => (role.privilege - privileges)

end
