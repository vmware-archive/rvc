#!/bin/sh
find lib -maxdepth 2 -name '*.rb' -exec ruby -Ilib -e "puts ARGV[0]; load ARGV[0]" {} \;
find lib/rvc/extensions -name '*.rb' -exec ruby -rrbvmomi -rrvc/vim -rrvc/util -Ilib -e 'x = File.basename(ARGV[0])[0...-3]; puts x; VIM.const_get(x)' {} \;
find lib/rvc/modules -name '*.rb' -exec ruby -rrbvmomi -rrvc/vim -rrvc/util -Ilib -e 'include RVC::Util; x = ARGV[0]; puts x; def rvc_alias(a,b=nil); end; def opts(s); end; def rvc_completor(a); end; def raw_opts(a,b); end; load(x)' {} \;
