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

require 'set'

module RVC

module ObjectWithFields
  module ClassMethods
    def fields inherited=true
      @fields ||= {}
      if inherited
        ancestors.select { |x| x.respond_to? :fields }.
                  map { |x| x.fields(false) }.
                  reverse.inject({}) { |b,v| b.merge v }
      else
        @fields
      end
    end

    def field name, &b
      name = name.to_s
      @fields ||= {}
      @fields[name] = RVC::Field.new(name).tap { |f| f.instance_eval &b }
    end
  end
  
  def field_properties names
    out = []
    names.each do |name|
      name = name.to_s
      field = self.class.fields[name]
      if field == nil
        nil
      elsif self.class < VIM::ManagedObject
        out += field.properties
      end
    end
    out.uniq
  end
  
  def perfmetrics names
    out = []
    names.each do |name|
      name = name.to_s
      field = self.class.fields[name]
      if field == nil
        nil
      else
        perfmetrics = field.perfmetrics 
        if perfmetrics.length > 0
          perfopts = field.perfmetric_settings.dup
          perfopts[:max_samples] ||= 5
          out << {:metrics => perfmetrics, :opts => perfopts}
        end
      end
    end
    out.uniq
  end

  def field name, props_values = {}, perf_values = {}
    name = name.to_s
    field = self.class.fields[name]
    if field == nil
      return nil
    elsif self.class < VIM::ManagedObject
      properties = field.properties
      if properties.all?{|x| props_values.has_key?(x)}
        props = properties.map{|x| props_values[x]}
      else
        *props = collect *field.properties
      end
      perfmetrics = field.perfmetrics
      if perfmetrics.length > 0
        if perfmetrics.all?{|x| perf_values.has_key?(x)}
          props += perfmetrics.map do |x| 
            perf_values[x]
          end
        else
          perfmgr = self._connection.serviceContent.perfManager
          perfopts = field.perfmetric_settings.dup
          perfopts[:max_samples] ||= 5
          stats = perfmgr.retrieve_stats [self], field.perfmetrics, perfopts
          props += field.perfmetrics.map do |x| 
            if stats[self] 
              stats[self][:metrics][x]
            else
              nil
            end
          end
        end
      end
    else
      props = []
      field.properties.each do |propstr|
        obj = self
        propstr.split('.').each { |prop| obj = obj.send(prop) }
        props << obj
      end
    end
    props = [self] if props.empty?
    field.block.call *props
  end
end

class Field
  ALL_FIELD_NAMES = Set.new

  def initialize name
    @name = name
    @summary = nil
    @properties = []
    @perfmetrics = []
    @perfmetric_settings = {}
    @block = nil
    @default = false
    ALL_FIELD_NAMES << name
  end

  def summary x=nil
    x ? (@summary = x) : @summary
  end

  def properties x=nil
    x ? (@properties.concat x) : @properties
  end

  def perfmetrics x=nil
    x ? (@perfmetrics.concat x) : @perfmetrics
  end

  def perfmetric_settings x=nil
    x ? (@perfmetric_settings.merge! x) : @perfmetric_settings
  end

  def block &x
    x ? (@block = x) : @block
  end

  def default val=true
    @default = val
  end

  def default?; @default; end

  def property prop
    @properties = [prop]
    @block = lambda { |x| x }
  end
end

end
