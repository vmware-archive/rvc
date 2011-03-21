require 'rvc/inventory'
require 'rvc/modules'
require 'rvc/util'
require 'rvc/path'
require 'rvc/context'
require 'rvc/completion'
require 'rvc/option_parser'
require 'rvc/shell'

RbVmomi::VIM.extension_dirs << File.join(File.dirname(__FILE__), "rvc/extensions")
