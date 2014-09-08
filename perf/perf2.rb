i = 0
loop do
  100.times do
    spawn "serf", "event", "-coalesce=false", "foo", i.to_s, out: File::NULL, err: File::NULL
    spawn "serf", "event", "-coalesce=false", "bar", i.to_s, out: File::NULL, err: File::NULL
    p i
    i += 1
  end
  sleep 2
  Process.waitall
end
