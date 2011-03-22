# Copyright (c) 2011 VMware, Inc.  All Rights Reserved.

require 'ffi'

module RVC::ReadlineFFI
  extend FFI::Library
  ffi_lib "readline.so"
  callback :rl_linebuf_func_t, [ :string, :int ], :bool
  attach_variable :rl_char_is_quoted_p, :rl_char_is_quoted_p, :rl_linebuf_func_t
  attach_variable :rl_line_buffer, :rl_line_buffer, :string
end

unless Readline.respond_to? :line_buffer
  def Readline.line_buffer
    RVC::ReadlineFFI.rl_line_buffer
  end
end

unless Readline.respond_to? :char_is_quoted=
  def Readline.char_is_quoted= fn
    RVC::ReadlineFFI.rl_char_is_quoted_p = fn
  end
end
