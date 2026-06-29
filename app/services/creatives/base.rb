# frozen_string_literal: true

module Creatives
  # Base class for a creative-type specification. Each concrete type is a
  # stateless class exposing `.type_key` and `.details`; `.spec` merges them.
  class Base
    def self.spec
      { type_key: type_key }.merge(details)
    end

    def self.type_key
      raise NotImplementedError, "#{name} must define .type_key"
    end

    def self.details
      {}
    end
  end
end
