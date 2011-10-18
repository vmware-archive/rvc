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

module RVC

module InventoryObject
  module ClassMethods
    def ls_properties
      %w()
    end

    def folder?
      false
    end

    def fields
      @fields ||= {}
    end

    def field name, &b
      name = name.to_s
      fields[name] = RVC::Field.new(name).tap { |f| f.instance_eval &b }
      define_method(name) { field name }
    end
  end

  def self.included m
    m.extend ClassMethods
  end

  attr_reader :rvc_parent, :rvc_arc

  def display_info
    puts "class: #{self.class.name}"
  end

  def ls_text r
    self.class.folder? ? '/' : ''
  end

  def traverse_one arc
    children[arc]
  end

  def children
    {}
  end

  def rvc_path
    [].tap do |a|
      cur = self
      while cur != nil
        a << [cur.rvc_arc, cur]
        cur = cur.rvc_parent
      end
      a.reverse!
    end
  end

  def rvc_path_str
    rvc_path.map { |k,v| k } * '/'
  end

  def rvc_link parent, arc
    return if @rvc_parent
    @rvc_parent = parent
    @rvc_arc = arc
  end

  def field name
    name = name.to_s
    field = self.class.fields[name]
    if field == nil
      return nil
    elsif self.class < VIM::ManagedObject
      *props = collect *field.properties
    else
      props = []
      field.properties.each do |propstr|
        obj = self
        propstr.split('.').each { |prop| obj = obj.send(prop) }
        props << obj
      end
    end
    field.block.call *props
  end
end

class FakeFolder
  include RVC::InventoryObject

  def initialize target, method
    @target = target
    @method = method
  end

  def children
    @target.send @method
  end

  def self.folder?
    true
  end

  def eql? x
    @target == x.instance_variable_get(:@target) &&
      @method == x.instance_variable_get(:@method)
  end

  def hash
    @target.hash ^ @method.hash
  end
end

class RootNode
  include RVC::InventoryObject

  def children
    $shell.connections
  end

  def self.folder?
    true
  end

  def pretty_print pp
    pp.text "Root"
  end
end

end

class RbVmomi::VIM
  include RVC::InventoryObject

  def children
    rootFolder.children
  end

  def self.folder?
    true
  end
end

class RVC::Field
  def initialize name
    @name = name
    @summary = nil
    @properties = []
    @block = nil
  end

  def summary x=nil
    x ? (@summary = x) : @summary
  end

  def properties x=nil
    x ? (@properties.concat x) : @properties
  end

  def block &x
    x ? (@block = x) : @block
  end

  def property prop
    @properties = [prop]
    @block = lambda { |x| x }
  end
end
