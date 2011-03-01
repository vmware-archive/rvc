require 'rvc/modules'
require 'rvc/util'
require 'rvc/path'
require 'rvc/context'
require 'rvc/completion'

RbVmomi::VIM.extension_dirs << File.join(File.dirname(__FILE__), "rvc/extensions")
