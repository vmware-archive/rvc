include RLUI::Util

def info path
  ds = lookup path
  expect ds, VIM::Datastore
  s = ds.summary
  info = ds.info
  puts "type: #{s.type}"
  puts "url: #{s.accessible ? s.url : '<inaccessible>'}"
  puts "uuid: #{info.vmfs.uuid}"
  puts "multipleHostAccess: #{s.multipleHostAccess}"
  puts "capacity: %0.2fGB" % (s.capacity.to_f/10**9)
  puts "free space: %0.2fGB" % (s.freeSpace.to_f/10**9)
end
