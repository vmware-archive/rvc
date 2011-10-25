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

  roots = args[:root].map { |x| lookup x }.flatten(1)
  terms = args[:term].map { |x| term x[1..-1] }

  candidates = leaves roots
  results = candidates.select { |r| terms.all? { |t| t[r] } }

  CMD.mark.mark opts[:mark], results

  i = 0
  cwd = $shell.fs.cur.rvc_path_str
  cwd_prefix = /^#{Regexp.escape cwd}\//
  results.each do |r|
    puts "#{i} #{r.rvc_path_str.gsub(cwd_prefix, '')}"
    CMD.mark.mark i.to_s, [r]
    i += 1
  end
end

def leaves roots
  leaves = Set.new
  new_nodes = roots
  while not new_nodes.empty?
    nodes = new_nodes
    new_nodes = Set.new
    nodes.each do |node|
      if node.class.folder?
        node.children.each { |k,v| v.rvc_link(node, k); new_nodes << v }
      else
        leaves << node
      end
    end
  end
  leaves
end

def term x
  case x
  when /^([\w.]+)(!)?(>=|<=|=|>|<|~)/
    lhs = $1
    negate = $2 != nil
    op = $3
    rhs = $'
    lambda do |o|
      a = o.field(lhs)
      a = [a].compact unless a.is_a? Enumerable
      return negate if a.empty?
      type = a.first.class
      fail "all objects in field #{lhs.inspect} must have the same type" unless a.all? { |x| x.is_a? type }
      b = coerce_str type, rhs
      a.any? do |x|
        p [x, op, b]
        case op
        when '='  then x == b
        when '>'  then x > b
        when '>=' then x >= b
        when '<'  then x < b
        when '<=' then x <= b
        when '~'  then x =~ Regexp.new(b)
        end
      end ^ negate
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
