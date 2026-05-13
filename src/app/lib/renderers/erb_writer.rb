# frozen_string_literal: true
require 'erb'

class ErbWriter
  def initialize(erb_file_path, config)
    @erb_file_path = erb_file_path
    @config = config
  end

  def write(io)
    erb = ERB.new(File.read @erb_file_path)
    result = erb.result_with_hash({config: @config})
    io.write(result)
  end

  def write_to_file(file_path)
    File.open(file_path, 'w') {|f| write f}
  end
end