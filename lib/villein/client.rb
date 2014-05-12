require 'json'
require 'villein/tags'

module Villein
  ##
  # Villein::Client allows you to order existing serf agent.
  # You will need RPC address and agent name to command.
  class Client
    ##
    # for serf command failures
    class SerfError < Exception; end

    ##
    # Error for the given argument exceeds the limit of serf when setting tags and sending events.
    class LengthExceedsLimitError < SerfError; end

    ##
    # Error for connection failures
    class SerfConnectionError < SerfError; end

    ##
    # Error when an called serf command is not found.
    class SerfCommandNotFound < SerfError; end

    ##
    # Error when an operation is not supported by the current version.
    class InsufficientVersionError < SerfError; end

    def initialize(rpc_addr, name: nil, serf: 'serf', silence: true)
      @rpc_addr = rpc_addr
      @name = name
      @serf = serf
      @silence = true
    end

    def silence?() !!@silence; end
    attr_writer :silence

    attr_reader :name, :rpc_addr, :serf

    ##
    # Returns a result of `serf info`.
    # This may raise InsufficientVersionError when `serf info` is not supported.
    def info
      JSON.parse call_serf('info', '-format', 'json')
    rescue SerfCommandNotFound
      raise InsufficientVersionError, 'serf v0.6.0 or later is required to run `serf info`.'
    end

    def event(name, payload, coalesce: true)
      options = []

      unless coalesce
        options << '-coalesce=false'
      end

      call_serf 'event', *options, name, payload
    end

    def query(name, payload, node: nil, tag: nil, timeout: nil, no_ack: false)
      # TODO: version check
      options = ['-format', 'json']

      if node
        node = [node] unless node.respond_to?(:each)
        node.each do |n|
          options << "-node=#{n}"
        end
      end

      if tag
        tag = [tag] unless tag.respond_to?(:each)
        tag.each do |t|
          options << "-tag=#{t}"
        end
      end

      if timeout
        options << "-timeout=#{timeout}"
      end

      if no_ack
        options << "-no-ack"
      end

      out = call_serf('query', *options, name, payload)
      JSON.parse(out)
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

      json = call_serf('members', *options)
      response = JSON.parse(json)

      response["members"]
    end

    ##
    # Returns Villein::Tags object for the current agent.
    # Villein::Tags provides high-level API for tagging agents.
    def tags
      @tags ||= Tags.new(self)
    end

    ##
    # Get tag from the agent.
    # Using Villein::Client#tags method is recommended. It provides high-level API via +Villein::Tags+.
    def get_tags
      me = members(name: self.name)[0]
      me["tags"]
    end

    ##
    # Remove tag from the agent.
    # Using Villein::Client#tags method is recommended. It provides high-level API via +Villein::Tags+.
    def delete_tag(key)
      call_serf 'tags', '-delete', key
    end

    ##
    # Set tag to the agent.
    # Using Villein::Client#tags method is recommended. It provides high-level API via +Villein::Tags+.
    def set_tag(key, val)
      call_serf 'tags', '-set', "#{key}=#{val}"
    end

    private 

    def call_serf(cmd, *args)
      status, out = IO.popen([@serf, cmd, "-rpc-addr=#{rpc_addr}", *args, err: [:child, :out]], 'r') do |io|
        _, s = Process.waitpid2(io.pid)
        [s, io.read]
      end

      unless status.success?
        case out
        when /^Error connecting to Serf agent:/
          raise SerfConnectionError, out.chomp
        when /exceeds limit of \d+ bytes$/
          raise LengthExceedsLimitError, out.chomp
        when /^Available commands are:/
          raise SerfCommandNotFound
        else
          raise SerfError, out.chomp
        end
      end

      out
    end
  end
end
