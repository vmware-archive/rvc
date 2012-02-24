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

require 'ffi'
require 'readline'

module RVC
module ReadlineFFI
  extend FFI::Library
  libreadline = ENV['RVC_READLINE'] == nil ? 'readline.so' : ENV['RVC_READLINE']
  ffi_lib libreadline
  callback :rl_linebuf_func_t, [ :string, :int ], :bool
  attach_variable :rl_char_is_quoted_p, :rl_char_is_quoted_p, :rl_linebuf_func_t
  attach_variable :rl_line_buffer, :rl_line_buffer, :string
end
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
