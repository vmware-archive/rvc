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
  when /^(\w+)(=|!=|>|>=|<|<=)/
    lambda do |o|
      v = o.field($1)
      v2 = coerce_str v.class, $'
      return false if v == nil and $2 != '='
      case $2
      when '=' then v == v2
      when '!=' then v != v2
      when '>' then v > v2
      when '>=' then v >= v2
      when '<' then v < v2
      when '<=' then v <= v2
      end
    end
  when /^\w+$/
    lambda { |o| o.field(x) }
  else
    err "failed to parse expression #{x.inspect}"
  end
end

def coerce_str type, v
  fail unless v.is_a? String
  if type <= Integer then v.to_i
  elsif type == Float then v.to_f
  elsif type == TrueClass or type == FalseClass then v == 'true'
  elsif type == NilClass then v == 'nil' ? nil : !nil
  elsif v == 'nil' then nil
  elsif type == String then v
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
