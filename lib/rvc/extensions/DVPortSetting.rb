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

include RVC::Util

class RbVmomi::VIM::DVPortSetting
  def dump_config vds, prefix, show_inheritance = true, show_uplinkinfo = true
    @show_inheritance = show_inheritance

    # map network respool to human-readable name
    if self.networkResourcePoolKey
       poolName  = translate_respool vds, self.networkResourcePoolKey, show_inheritance
    end
    puts_policy "#{prefix}blocked:", self.blocked
    puts_policy("#{prefix}vlan:", self.vlan, "", nil) { |v| translate_vlan v }
    if self.networkResourcePoolKey
       puts        "#{prefix}network resource pool: #{poolName}"
    end
    p = self.inShapingPolicy
    if p
       puts        "#{prefix}Rx Shaper: "
       puts_policy "#{prefix}  enabled:", p.enabled
       avg_bw = p.averageBandwidth
       puts_policy("#{prefix}  average bw:", avg_bw, "b/sec"){|v|metric(v)}
       puts_policy("#{prefix}  peak bw:", p.peakBandwidth, "b/sec"){|v|metric(v)}
       puts_policy("#{prefix}  burst size:", p.burstSize, "B"){|v|metric(v)}
    end
    p = self.outShapingPolicy
    if p
       puts        "#{prefix}Tx Shaper:"
       puts_policy "#{prefix}  enabled:", p.enabled
       avg_bw = p.averageBandwidth
       puts_policy("#{prefix}  average bw:", avg_bw, "b/sec") { |v| metric(v) }
       puts_policy("#{prefix}  peak bw:", p.peakBandwidth, "b/sec") {|v| metric(v)}
       puts_policy("#{prefix}  burst size:", p.burstSize, "B") {|v| metric(v)}
    end
    if show_uplinkinfo
      p = self.uplinkTeamingPolicy
      if p
         puts        "#{prefix}Uplink Teaming Policy:"
         puts_policy "#{prefix}  policy:", p.policy  #XXX map the strings values
         puts_policy "#{prefix}  reverse policy:", p.reversePolicy
         puts_policy "#{prefix}  notify switches:", p.notifySwitches
         puts_policy "#{prefix}  rolling order:", p.rollingOrder
         c = p.failureCriteria
         if c
            puts        "#{prefix}  Failure Criteria: "
            puts_policy "#{prefix}    check speed:", c.checkSpeed
            puts_policy("#{prefix}    speed:", c.speed, "Mb/sec")# { |v| metric(v) }
            puts_policy "#{prefix}    check duplex:", c.checkDuplex
            puts_policy "#{prefix}    full duplex:", c.fullDuplex
            puts_policy "#{prefix}    check error percentage:",  c.checkErrorPercent
            puts_policy "#{prefix}    max error percentage:", c.percentage, "%"
            puts_policy "#{prefix}    check beacon:", c.checkBeacon
         end
         o = p.uplinkPortOrder
         if o
            puts        "#{prefix}  Uplink Port Order:"
            puts_policy("#{prefix}    active:", o,"", :activeUplinkPort){|v|v.join(',')}
            puts_policy("#{prefix}    standby:",o,"",:standbyUplinkPort){|v|v.join(',')}
         end
      end
    end
    p = self.securityPolicy
    if p
       puts        "#{prefix}Security:"
       puts_policy "#{prefix}  allow promiscuous mode:", p.allowPromiscuous
       puts_policy "#{prefix}  allow mac changes:", p.macChanges
       puts_policy "#{prefix}  allow forged transmits:", p.forgedTransmits
       puts_policy "#{prefix}enable ipfix monitoring:", self.ipfixEnabled
       puts_policy "#{prefix}forward all tx to uplink:", self.txUplink
    end
  end

  def puts_policy prefix, policy, suffix = "", prop = :value, &b
    b ||= lambda { |v| v }
    if policy
       if prop != nil
          v = policy.send(prop)
       else
          v = policy
       end
       print "#{prefix} #{b.call(v)}#{suffix}"
       if @show_inheritance and policy.inherited == false
          puts "*"
       else
          puts ""
       end
    end
  end
end
