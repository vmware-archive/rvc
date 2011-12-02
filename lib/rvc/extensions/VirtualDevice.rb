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

class RbVmomi::VIM::VirtualDevice
  include RVC::InventoryObject
  attr_accessor :rvc_vm

  # Stable name based on the device key, unit number, etc.
  # May be overridden in subclasses.
  def name
    self.class.to_s =~ /^(?:Virtual)?(?:Machine)?(\w+?)(?:Card|Device|Controller)?$/
    type = $1 ? $1.downcase : 'device'
    "#{type}-#{key}"
  end

  def ls_text r
    tags = []
    tags << (connectable.connected ? :connected : :disconnected) if props.member? :connectable
    " (#{self.class}): #{deviceInfo.summary}; #{tags * ' '}"
  end

  def display_info
    super
    devices, = rvc_vm.collect 'config.hardware.device'
    puts "label: #{deviceInfo.label}"
    puts "summary: #{deviceInfo.summary}"
    puts "key: #{key}"
    if controllerKey
      controller = devices.find { |x| x.key == controllerKey }
      puts "controller: #{controller.name}" if controller
    end
    puts "unit number: #{unitNumber}" if unitNumber
    if connectable
      puts "connectivity:"
      puts " connected: #{connectable.connected}"
      puts " start connected: #{connectable.startConnected}"
      puts " guest control: #{connectable.allowGuestControl}"
      puts " status: #{connectable.status}"
    end
  end
end

