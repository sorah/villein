# Villein - Use `serf` from Ruby

Use [serf](https://www.serfdom.io/) from Ruby.

## Installation

Add this line to your application's Gemfile:

    gem 'villein'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install villein

## Requirements

- Ruby 2.0.0+
- Serf
  - v0.6.0 or later is required to use `query` and `info` method

## Usage

### Use for existing `serf agent`

``` ruby
require 'villein'

# You have to tell RPC address and node name.
client = Villein::Client.new('localhost:7373', name: 'testnode')
```

### Start new `serf agent` then use

``` ruby
require 'villein'

client = Villein::Agent.new

# Start the agent
client.start!

# Stop the agent
client.stop!

# Inspect the status
p client.running?
p client.stopped?

# You can specify many options to Agent.new...
# :node, :rpc_addr, :bind, :iface, :advertise, :discover,
# :config_file, :config_dir, :discover, :join, :snapshot, :encrypt, :profile,
# :protocol, :event_handlers, :replay, :tags, :tags_file, :log_level
```

### join and leave

``` ruby
client.join('x.x.x.x')
client.join('x.x.x.x', replay: true)
client.leave()
client.force_leave('other-node')
```

### Sending user events

``` ruby
# Send user event
client.event('my-event', 'payload')
client.event('my-event', 'payload', coalesce: true)
```

### Querying

``` ruby
client.query('hey', '') #=> {"Acks"=>["XXX.local"], "Responses"=>{"XXX"=>"..."}}
```

### Retrieve member list

``` ruby
# Retrieve member list
client.members
# =>
#   [
#     {
#      "name"=>"testnode", "addr"=>"x.x.x.x:7946", "port"=>7946,
#      "tags"=>{}, "status"=>"alive",
#      "protocol"=>{"max"=>4, "min"=>2, "version"=>4}
#     }
#   ]

# You can use some filters.
# The filters will be passed `serf members` command directly, so be careful
# to escape regexp-like strings!
client.members(name: 'foo')
client.members(status: 'alive')
client.members(tags: {foo: 'bar'})
```

### (Agent only) hook events

``` ruby
agent = Villein::Agent.new
agent.start!

agent.on_member_join do |event|
  p event # => #<Villein::Event>
  p event.type # => 'member-join'
  p event.self_name
  p event.self_tags # => {"TAG1" => 'value1'}
  p event.members # => [{name: "the-node", address:, tags: {tag1: 'value1'}}]
  p event.user_event # => 'user'
  p event.query_name
  p event.ltime
  p event.payload #=> "..."
end

agent.on_member_leave { |event| ... }
agent.on_member_failed { |event| ... }
agent.on_member_update { |event| ... }
agent.on_member_reap { |event| ... }
agent.on_user_event { |event| ... }
agent.on_query { |event| ... }

# Catch any events
agent.on_event { |event| p event }

# Catch the agent stop
agent.on_event { |status|
  # `status` will be a Process::Status, on unexpectedly exits.
  p status
}
```

### (Agent only) Respond to query events

``` ruby
agent = Villein::Agent.new
agent.start!

agent.respond("hey") { "hello" }
```

```
$ serf query hey
Query 'hey' dispatched
Ack from 'XXX.local'
Response from 'XXX.local': hello
Total Acks: 1
Total Responses: 1
```

## Advanced

TBD

### Specifying location of `serf` command

### Logging `serf agent`

## FAQ

### Why I have to tell node name?

## Contributing

1. Fork it ( https://github.com/sorah/villein/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
