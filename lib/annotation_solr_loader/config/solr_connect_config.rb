class SolrConnectConfig
    @@configuration = {}

    def self.set(property_name, value)
      @@configuration[property_name] = value
    end

    def self.get(property_name)
      @@configuration[property_name]
    end

    def self.setup
      yield self
    end
  end
