# frozen_string_literal: true

class DomainUtil
  def self.normalize_name(name)
    name.gsub(/[\.\W]/, '_')
  end
end
