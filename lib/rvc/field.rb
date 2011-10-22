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

module ObjectWithFields
  module ClassMethods
    def fields inherited=true
      @fields ||= {}
      if inherited and superclass.respond_to? :fields
        superclass.fields.merge @fields
      else
        @fields.dup
      end
    end

    def field name, &b
      name = name.to_s
      @fields ||= {}
      @fields[name] = RVC::Field.new(name).tap { |f| f.instance_eval &b }
    end
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

class Field
  def initialize name
    @name = name
    @summary = nil
    @properties = []
    @block = nil
    @default = false
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

  def default
    @default = true
  end

  def default?; @default; end

  def property prop
    @properties = [prop]
    @block = lambda { |x| x }
  end
end

end
