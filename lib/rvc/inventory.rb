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

require 'rvc/field'

module RVC

module InventoryObject
  include ObjectWithFields
  extend ObjectWithFields::ClassMethods

  module ClassMethods
    include ObjectWithFields::ClassMethods

    def ls_r
      ""
    end

    def ls_properties
      %w()
    end

    def folder?
      false
    end

    def traverse?
      false
    end
  end

  def self.included m
    m.extend ClassMethods
  end

  field 'rel_path' do
    block { |me| me.rvc_relative_path_str($shell.fs.cur) }
  end

  attr_reader :rvc_parent, :rvc_arc

  def display_info
    puts "class: #{self.class.name}"
  end

  def ls_text r
    self.class.folder? ? '/' : ''
  end

  def traverse_one arc
    rvc_children[arc]
  end

  def children
    {}
  end
  
  def rvc_children
    out = self.children
    methods.grep(/rvc_list_children_/).each do |method|
      out.merge!(self.send(method))
    end
    out
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

  def rvc_relative_path ref
    my_path = rvc_path
    ref_path = ref.rvc_path
    ref_objs = Set.new(ref_path.map { |x| x[1] })
    common = my_path.take_while { |x| ref_objs.member? x[1] }
    fail unless common
    path_to_ref = my_path.reverse.take_while { |x| x[1] != common.last[1] }.reverse
    num_ups = ref_path.size - common.size
    ups = (['..']*num_ups).zip(ref_path.reverse[1..-1].map(&:first))
    ups + path_to_ref
  end

  def rvc_relative_path_str ref
    rvc_relative_path(ref).map { |k,v| k } * '/'
  end

  def rvc_link parent, arc
    return if @rvc_parent
    @rvc_parent = parent
    @rvc_arc = arc
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

  def initialize shell
    @shell = shell
  end

  def children
    @shell.connections
  end

  def self.folder?
    true
  end

  def pretty_print pp
    pp.text "Root"
  end
end

end
