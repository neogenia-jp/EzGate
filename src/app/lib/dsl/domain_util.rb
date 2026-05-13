# frozen_string_literal: true

module Dsl
  class DomainUtil
    def self.normalize_name(name)
      name.gsub(/[\.\W]/, '_')
    end
  end
end
