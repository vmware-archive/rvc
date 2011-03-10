module RVC

class CmdModule < Module
  def initialize
    @opts = {}
    super
  end

  def commands
    @commands ||= (public_methods(false) - CmdModule.instance_methods).reject { |x| x.to_s[0..0] == '_' }
  end

  def opts cmd, &b
    @opts[cmd] = b
  end

  def opts_for cmd
    @opts[cmd]
  end
end

BULTIN_MODULE_PATH = [File.expand_path(File.join(File.dirname(__FILE__), 'modules'))]
ENV_MODULE_PATH = (ENV['RVC_MODULE_PATH'] || '').split ':'

def self.reload_modules verbose=true
  MODULES.clear
  MODULES['custom'] = CmdModule.new
  module_path = (BULTIN_MODULE_PATH+ENV_MODULE_PATH).select { |d| File.directory?(d) }
  globs = module_path.map { |d| File.join(d, '*.rb') }
  Dir.glob(globs) do |f|
    module_name = File.basename(f)[0...-3]
    puts "loading #{module_name} from #{f}" if verbose
    code = File.read f
    unless MODULES.member? module_name
      m = CmdModule.new
      CMD.define_singleton_method(module_name.to_sym) { m }
      MODULES[module_name] = m
    end
    MODULES[module_name].instance_eval code, f
  end
end

def self.reload_rc
  rcfile = "#{ENV['HOME']}/.rvcrc"
  load rcfile if File.exists? rcfile
end

end
