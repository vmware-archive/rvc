opts :foo do
  summary "Foo it"
end

rvc_alias :foo, :foo

def foo
  42
end
