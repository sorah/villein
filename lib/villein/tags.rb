module Villein
  class Tags
    def initialize(client) # :nodoc:
      @client = client
      reload
    end

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

    def [](key)
      @tags[key.to_s]
    end

    def delete(key)
      key = key.to_s

      @client.delete_tag key
      @tags.delete key

      nil
    end

    def to_h
      # duping
      Hash[@tags.map{ |k,v| [k,v] }]
    end

    def reload
      @tags = @client.get_tags
      self
    end
  end
end
