require 'villein'

agent = Villein::Agent.new(node: 'perf', rpc_addr: '127.0.0.1:17373', bind: "127.0.0.1:17946", parallel_events: !!ARGV[0])

agent.on_user_event do |event|
  p event
end

agent.respond('myquery') do |event|
  p event
  Time.now.to_s
end

agent.auto_stop
agent.start!

sleep
