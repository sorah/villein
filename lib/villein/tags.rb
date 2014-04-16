module Villein
  class Tags
    def initialize(client) # :nodoc:
      @client = client
      reload
    end

    ##
    # Set tag of the agent.
    def []=(key, value)
      if value
        key = key.to_s
        value = value.to_s
        @client.set_tag(key, value)
        @tags[key] = value
      else
        self.delete key.to_s
      end
    end

    ##
    # Returns tag of the agent.
    # Note that this method is cached, you have to call +reload+ method to flush them.
    def [](key)
      @tags[key.to_s]
    end

    ##
    # Remove tag from the agent.
    def delete(key)
      key = key.to_s

      @client.delete_tag key
      @tags.delete key

      nil
    end

    def inspect
      "#<Villein::Tags #{@tags.inspect}>"
    end

    ##
    # Returns +Hash+ of tags.
    def to_h
      # duping
      Hash[@tags.map{ |k,v| [k,v] }]
    end

    ##
    # Reload tags of the agent.
    def reload
      @tags = @client.get_tags
      self
    end
  end
end
