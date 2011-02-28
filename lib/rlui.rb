require 'rlui/modules'
require 'rlui/util'
require 'rlui/path'
require 'rlui/context'
require 'rlui/completion'

RbVmomi::VIM.extension_dirs << File.join(File.dirname(__FILE__), "rlui/extensions")
