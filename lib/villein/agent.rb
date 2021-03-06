require 'socket'
require 'timeout'
require 'thread'
require 'villein/client'
require 'villein/event'

module Villein
  ##
  # Villein::Agent allows you to start new serf agent.
  # Use this when you need to start and manage the serf agents from ruby process.
  class Agent < Client
    class AlreadyStarted < Exception; end
    class NotRunning < Exception; end
    class ResponderExists < Exception; end

    EVENT_HANDLER_NATIVE = File.expand_path(File.join(__dir__, '..', '..', 'misc', 'villein-event-handler'))
    EVENT_HANDLER_RB = File.expand_path(File.join(__dir__, '..', '..', 'misc', 'villein-event-handler.rb'))

    EVENT_HANDLER = if File.exist?(EVENT_HANDLER_NATIVE)
                      EVENT_HANDLER_NATIVE
                    else
                      EVENT_HANDLER_RB
                    end
    def initialize(serf: 'serf',
                   node: Socket.gethostname,
                   rpc_addr: '127.0.0.1:7373', bind: nil, iface: nil, advertise: nil,
                   config_file: nil, config_dir: nil,
                   discover: false, join: nil, snapshot: nil,
                   encrypt: nil, profile: nil, protocol: nil,
                   event_handlers: [], replay: nil,
                   tags: {}, tags_file: nil,
                   async_query: true,
                   parallel_events: false,
                   log_level: :info, log: File::NULL,
                   raise_error_on_event_listener_fail: false,
                   villein_handler: EVENT_HANDLER)
      @serf = serf
      @name = node
      @rpc_addr = rpc_addr
      @bind, @iface, @advertise = bind, iface, advertise
      @config_file, @config_dir = config_file, config_dir
      @discover, @join, @snapshot = discover, join, snapshot
      @encrypt, @profile, @protocol = encrypt, profile, protocol
      @custom_event_handlers, @replay = event_handlers, replay
      @initial_tags, @tags_file = tags, tags_file
      @async_query, @parallel_events = async_query, parallel_events
      @log_level, @log = log_level, log
      @raise_error_on_event_listener_fail = raise_error_on_event_listener_fail
      @villein_handler = villein_handler

      @hooks = {}
      @responders = {}

      @pid, @exitstatus = nil, nil
      @pid_lock = Mutex.new
    end

    attr_reader :pid, :exitstatus

    ##
    # Returns true when the serf agent has started
    def started?
      !!@pid
    end

    ##
    # Returns true when the serf agent has started, but stopped for some reason.
    # Use Agent#exitstatus to get <code>Process::Status</code> object.
    def dead?
      !!@exitstatus
    end

    ##
    # Return true when the agent has received events at least once.
    # Useful to wait serf for ready to use.
    def ready?
      running? && @event_received
    end

    ##
    # Returns true when the serf agent is running (it has started and not dead yet).
    def running?
      started? && !dead?
    end

    # Start the serf agent.
    def start!
      @pid_lock.synchronize do
        raise AlreadyStarted if running?

        @event_received = false

        start_listening_events
        start_process
        start_watchdog
      end
    end

    ##
    # Stop the serf agent.
    # After +timeout_sec+ seconds elapsed, it will attempt to KILL if the agent is still running.
    def stop!(timeout_sec = 10)
      @pid_lock.synchronize do
        raise NotRunning unless running?

        Process.kill(:INT, @pid)

        stop_watchdog
        call_hooks 'stop', nil

        kill_process(timeout_sec)

        stop_listening_events

        @pid = nil
      end
    end

    ##
    # Blocks until #ready? become true.
    def wait_for_ready
      sleep 0.1 until ready?
    end

    ##
    # Add +at_exit+ hook to safely stop at exit of current ruby process.
    # Note that +Kernel#.at_exit+ hook won't run when Ruby has crashed.
    def auto_stop
      at_exit { self.stop! if self.running? }
    end

    %w(member_join member_leave member_failed member_update member_reap
       user query stop event).each do |event|

      define_method(:"on_#{event}") do |&block|
        add_hook(event, block)
      end
    end

    alias_method :on_user_event, :on_user

    ##
    # Command line arguments to start serf-agent.
    def command
      cmd = [@serf, 'agent']

      cmd << ['-node', @name] if @name
      cmd << '-replay' if @replay
      cmd << '-discover' if @discover

      @initial_tags.each do |key, val|
        cmd << ['-tag', "#{key}=#{val}"]
      end

      cmd << [
        '-event-handler',
        [@villein_handler, *event_listener_addr].join(' ')
      ]

      @custom_event_handlers.each do |handler|
        cmd << ['-event-handler', handler]
      end

      %w(bind iface advertise config-file config-dir
         encrypt join log-level profile protocol rpc-addr
         snapshot tags-file).each do |key|

        val = instance_variable_get("@#{key.gsub(/-/,'_')}")
        cmd << ["-#{key}", val] if val
      end

      cmd.flatten.map(&:to_s)
    end

    ##
    # Respond to query events.
    # Raises error when override is false and responder for given query name already exists.
    def respond(name, override: false, &block)
      name = name.to_s
      if !override && @responders[name]
        raise ResponderExists, "Responder for #{name} already exists. To force, pass `override: true`"
      end

      @responders[name] = block
    end

    private

    def start_process
      @exitstatus = nil

      actual = -> { @pid = spawn(*command, out: @log, err: @log) }

      if defined? Bundler
        Bundler.with_clean_env(&actual)
      else
        actual.call
      end
    end

    def kill_process(timeout_sec = 10)
      begin
        begin
          timeout(timeout_sec) { Process.waitpid(@pid) }
        rescue Timeout::Error
          Process.kill(:KILL, @pid)
        end
      rescue Errno::ECHILD
      end
    end

    def start_watchdog
      return if @watchdog && @watchdog.alive?

      @watchdog = Thread.new do
        pid, @exitstatus = Process.waitpid2(@pid)
        call_hooks(:stop, @exitstatus)
      end
    end

    def stop_watchdog
      @watchdog.kill if @watchdog && @watchdog.alive?
    end

    def event_listener_addr
      raise "event listener not started [BUG]" unless @event_listener_server

      addr = @event_listener_server.addr
      [addr[-1], addr[1]]
    end

    def start_listening_events
      return if @event_listener_thread

      @event_listener_server = TCPServer.new('localhost', 0)
      @event_queue = Queue.new
      @event_listener_thread = Thread.new do
        event_listener_loop
      end

      @event_dispatcher_thread = Thread.new do
        event_dispatcher_loop
      end

      @event_listener_thread.abort_on_exception = @raise_error_on_event_listener_fail
      @event_dispatcher_thread.abort_on_exception = @raise_error_on_event_listener_fail
    end

    def stop_listening_events
      if @event_listener_thread && @event_listener_thread.alive?
        @event_listener_thread.kill
      end

      if @event_listener_dispatcher && @event_listener_dispatcher.alive?
        @event_listener_thread.kill
      end

      if @event_listener_server && !@event_listener_server.closed?
        @event_listener_server.close
      end

      @event_listener_thread = nil
      @event_listener_dispatcher = nil
      @event_queue = nil
      @event_listener_server = nil
    end

    def event_listener_loop
      while sock = @event_listener_server.accept
        sock_delegated = false
        begin
          buf, obuf = "", ""
          loop do
            socks, _, _ = IO.select([sock], nil, nil, 5)
            break unless socks

            begin
              socks[0].read_nonblock(2048, obuf)
            rescue EOFError
              break
            end

            buf << obuf
            break if socks[0].eof?
          end
          event = parse_event(buf)
          next unless event

          # XXX:
          if event.type == 'query'
            if @async_query
              sock_delegated = true
              Thread.new(event, sock) do |ev, so|
                handle_query ev, so
              end
            else
              handle_query event, sock
            end
          else
            if @parallel_events
              Thread.new(event) do |ev|
                handle_event event
              end
            else
              @event_queue << event
            end
          end
        ensure
          sock.close if !sock_delegated && !sock.closed?
        end
      end
    end

    def event_dispatcher_loop
      while event = @event_queue.pop
        handle_event event
      end
    end

    def parse_event(payload)
      env_payload, input = payload.split(/\0\0/,2) # ['name=val', 'name=val', '', 'input']
      return unless env_payload && input

      env = Hash[env_payload.split(/\0/).map do |line|
        line.split(/=/,2)
      end]

      Event.new(env, payload: input)
    rescue JSON::ParserError
      # do nothing
      return nil
    end

    def handle_event(event)
      @event_received = true
      call_hooks event.type.gsub(/-/, '_'), event
      call_hooks 'event', event
    rescue Exception => e
      $stderr.puts "Exception during handling event: #{event.inspect}"
      $stderr.puts "#{e.class}: #{e.message}"
      $stderr.puts e.backtrace.map { |_| _.prepend("\t") }
    end

    def handle_query(event, sock)
      @event_received = true
      call_hooks event.type.gsub(/-/, '_'), event
      call_hooks 'event', event

      if event.type == 'query' && @responders[event.query_name]
        sock.write(@responders[event.query_name].call(event))
      end
    rescue Exception => e
      $stderr.puts "Exception during handling query: #{event.inspect}"
      $stderr.puts "#{e.class}: #{e.message}"
      $stderr.puts e.backtrace.map { |_| _.prepend("\t") }
    ensure
      sock.close unless sock.closed?
    end

    def hooks_for(name)
      @hooks[name.to_s] ||= []
    end

    def call_hooks(name, *args)
      hooks_for(name).each do |hook|
        hook.call(*args)
      end
      nil
    end

    def add_hook(name, block)
      hooks_for(name) << block
    end
  end
end

