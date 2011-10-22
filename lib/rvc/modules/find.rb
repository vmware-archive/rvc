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

opts :find do
  summary "Find objects matching certain criteria"
  arg :args, "Paths or +terms", :required => false, :multi => true
  opt :mark, "Store results in an aggregate mark", :default => 'A'
end

rvc_alias :find

def find args, opts
  args = args.group_by do |arg|
    case arg
    when /^\+/ then :term
    else :root
    end
  end

  args[:root] ||= ['.']
  args[:term] ||= []

  # TODO
  err "only 1 root supported" if args[:root].size > 1
  root_name = args[:root].first
  root = lookup_single root_name

  terms = args[:term].map { |x| term x[1..-1] }

  candidates = root.children.map { |k,v| FindResult.new [root_name,k], v }
  results = candidates.select { |r| terms.all? { |t| t[r.obj] } }

  CMD.mark.mark opts[:mark], results.map(&:obj)

  i = 0
  results.each do |r|
    display_path = r.path.reject { |x| x == '.' }.join('/')
    puts "#{i} #{display_path}"
    CMD.mark.mark i.to_s, [r.obj]
    i += 1
  end
end

def term x
  case x
  when /^!/
    t2 = term $'
    lambda { |o| !t2[o] }
  when /^([\w.]+)(=|!=|>|>=|<|<=|~)/
    lhs = $1
    op = $2
    rhs = $'
    lambda do |o|
      a = o.field(lhs)
      b = coerce_str a.class, rhs
      return false if a == nil and op != '='
      case op
      when '=' then a == b
      when '!=' then a != b
      when '>' then a > b
      when '>=' then a >= b
      when '<' then a < b
      when '<=' then a <= b
      when '~' then a =~ Regexp.new(b)
      end
    end
  when /^\w+$/
    lambda { |o| o.field(x) }
  else
    err "failed to parse expression #{x.inspect}"
  end
end

def coerce_str type, v
  fail "expected String, got #{v.class}" unless v.is_a? String
  if type <= Integer then v.to_i
  elsif type == Float then v.to_f
  elsif type == TrueClass or type == FalseClass then v == 'true'
  elsif type == NilClass then v == 'nil' ? nil : !nil
  elsif v == 'nil' then nil
  elsif type == String then v
  elsif type.respond_to? :parse then type.parse(v)
  else fail "unexpected coercion type #{type}"
  end
end

class FindResult
  attr_reader :path, :obj

  def initialize path, obj
    @path = path
    @obj = obj
  end
end
