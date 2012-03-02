# Copyright (c) 2012 VMware, Inc.  All Rights Reserved.
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
require 'uri'

module RVC

class URIParser
  # XXX comments
  # TODO certdigest
  URI_REGEX = %r{
    ^
    (?:
     (\w+):// # scheme
    )?
    (?:
      ([^@:]+) # username
      (?::
        ([^@]*) # password
      )?
      @
    )?
    ([^@:]+) # host
    (?::(\d{1,5}))? # port
    $
  }x

  # Loosely parse a URI. This is more forgiving than a standard URI parser.
  def self.parse str
    match = URI_REGEX.match str
    Util.err "invalid URI" unless match

    URI::Generic.build({}).tap do |uri|
      uri.scheme = match[1] || 'vim'
      uri.user = match[2] if match[2]
      uri.password = match[3] if match[3]
      uri.host = match[4] if match[4]
      uri.port = match[5].to_i if match[5]
    end
  end
end

end
