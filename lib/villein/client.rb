require 'json'
require 'villein/tags'

module Villein
  class Client
    def initialize(rpc_addr, name: nil, serf: 'serf', silence: true)
      @rpc_addr = rpc_addr
      @name = name
      @serf = serf
      @silence = true
    end

    def silence?() !!@silence; end
    attr_writer :silence

    attr_reader :name, :rpc_addr, :serf

    def event(name, payload, coalesce: true)
      options = []

      unless coalesce
        options << '-coalesce=false'
      end

      call_serf 'event', *options, name, payload
    end

    def join(addr, replay: false)
      options = []

      if replay
        options << '-replay'
      end

      call_serf 'join', *options, addr
    end

    def leave
      call_serf 'leave'
    end

    def force_leave(node)
      call_serf 'force-leave', node
    end

    def members(status: nil, name: nil, tags: {})
      options = ['-format', 'json']

      options.push('-status', status.to_s) if status
      options.push('-name', name.to_s) if name

      tags.each do |tag, val|
        options.push('-tag', "#{tag}=#{val}")
      end

      json = IO.popen(['serf', 'members', "-rpc-addr=#{rpc_addr}", *options], 'r', &:read)
      response = JSON.parse(json)

      response["members"]
    end

    def tags
      @tags ||= Tags.new(self)
    end

    def get_tags
      me = members(name: self.name)[0]
      me["tags"]
    end

    def delete_tag(key)
      call_serf 'tags', '-delete', key
    end

    def set_tag(key, val)
      call_serf 'tags', '-set', "#{key}=#{val}"
    end

    private 

    def call_serf(cmd, *args)
      options = {}

      if silence?
        options[:out] = File::NULL
        options[:err] = File::NULL
      end

      system @serf, cmd, "-rpc-addr=#{rpc_addr}", *args, options
    end
  end
end
