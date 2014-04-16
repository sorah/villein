module Villein
  class Event
    MEMBERS_EVENT = %w(member-join member-leave member-failed member-update member-reap)

    def initialize(env={}, payload: nil)
      @type = env['SERF_EVENT']
      @self_name = env['SERF_SELF_NAME']
      @self_tags = Hash[env.select{ |k, v| /^SERF_TAG_/ =~ k }.map { |k, v| [k.sub(/^SERF_TAG_/, ''), v] }]
      @user_event = env['SERF_USER_EVENT']
      @query_name = env['SERF_QUERY_NAME']
      @user_ltime = env['SERF_USER_LTIME']
      @query_ltime = env['SERF_QUERY_LTIME']
      @payload = payload
    end

    attr_reader :type, :self_name, :self_tags, :user_event, :query_name, :user_ltime, :query_ltime, :payload

    def ltime
      user_ltime || query_ltime
    end

    ##
    # Parse and returns member list in Array<Hash> when available.
    # Always return +nil+ if the event type is not +member-*+.
    def members
      return nil unless MEMBERS_EVENT.include?(type)
      @members ||= begin
        payload.each_line.map do |line|
          name, address, _, tags_str = line.chomp.split(/\t/)
          {name: name, address: address, tags: parse_tags(tags_str)}
        end
      end
    end

    private

    def parse_tags(str)
      # "aa=b=,,c=d,e=f,g,h,i=j" => {"aa"=>"b=,", "c"=>"d", "e"=>"f,g,h", "i"=>"j"}
      tokens = str.scan(/(.+?)([,=]|\z)/).flatten

      pairs = []
      stack = []

      while token = tokens.shift
        case token
        when "="
          stack << token
        when ","
          stack << token

          if tokens.first != ',' && 2 <= stack.size
            pairs << stack.dup
            stack.clear
          end
        else
          stack << token
        end
      end
      pairs << stack.dup unless stack.empty?

      pairs = pairs.inject([]) { |r, pair|
        if !pair.find{ |_| _ == '='.freeze } && r.last
          r.last.push(*pair) 
          r
        else
          r << pair
        end
      }
      pairs.each(&:pop)
      Hash[pairs.map{ |_| _.join.split(/=/,2) }]
    end
  end
end
