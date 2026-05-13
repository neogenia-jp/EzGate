# frozen_string_literal: true

require_relative 'erb_writer'

class BaseRenderer
  def initialize(config)
    @config = config
  end

  def render(template_path:, output_path:)
    ErbWriter.new(template_path, @config).write_to_file(output_path)
  end
end
