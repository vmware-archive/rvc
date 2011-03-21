module RVC

class Shell

  def initialize
    @persist_ruby = false
    @ruby_context = RubyEvalContext.new
  end

  def eval_input input
    if input == '//'
      @persist_ruby = !@persist_ruby
      return
    end

    if input[0..0] == '!'
      system_fg input[1..-1]
      return
    end

    ruby = @persist_ruby
    if input =~ /^\//
      input = $'
      ruby = !ruby
    end

    begin
      if ruby
        eval_ruby input
      else
        eval_command input
      end
    rescue SystemExit, IOError
      raise
    rescue UserError, RuntimeError, RbVmomi::Fault
      if ruby
        puts "#{$!.class}: #{$!.message}"
        puts $!.backtrace * "\n"
      else
        case $!
        when RbVmomi::Fault, UserError
          puts $!.message
        else
          puts "#{$!.class}: #{$!.message}"
        end
      end
    rescue Interrupt
      puts
    rescue Exception
      puts "#{$!.class}: #{$!.message}"
      puts $!.backtrace * "\n"
    end
  end

  def eval_command input
    cmd, *args = Shellwords.shellwords(input)
    return unless cmd
    err "invalid command" unless cmd.is_a? String
    case cmd
    when RVC::Context::MARK_REGEX
      CMD.basic.cd cmd
    else
      if cmd.include? '.'
        module_name, cmd, = cmd.split '.'
      elsif ALIASES.member? cmd
        module_name, cmd, = ALIASES[cmd].split '.'
      else
        err "unknown alias #{cmd}"
      end

      m = MODULES[module_name] or err("unknown module #{module_name}")

      opts_block = m.opts_for(cmd.to_sym)
      parser = RVC::OptionParser.new cmd, &opts_block

      begin
        args, opts = parser.parse args
      rescue Trollop::HelpNeeded
        parser.educate
        return
      end

      if parser.has_options?
        m.send cmd.to_sym, *(args + [opts])
      else
        m.send cmd.to_sym, *args
      end
    end
    nil
  end

  def eval_ruby input
    result = @ruby_context.do_eval input
    if input =~ /\#$/
      CMD.basic.type result.class.wsdl_name
    else
      pp result
    end
    nil
  end

  def prompt
    "#{$context.display_path}#{@persist_ruby ? '~' : '>'} "
  end
end

class RubyEvalContext
  def initialize
    @binding = binding
  end

  def do_eval input
    eval input, @binding
  end

  def this
    $context.cur
  end

  def dc
    $context.lookup("~")
  end

  def conn
    (dc || return)._connection
  end

  def method_missing sym, *a
    str = sym.to_s
    if a.empty?
      if MODULES.member? str
        MODULES[str]
      elsif $context.marks.member?(str)
        $context.marks[str].obj
      elsif str[0..0] == '_' && $context.marks.member?(str[1..-1])
        $context.marks[str[1..-1]].obj
      else
        super
      end
    else
      super
    end
  end
end

end
