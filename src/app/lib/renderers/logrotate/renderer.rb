# frozen_string_literal: true

require_relative '../../erb_writer'

module Logrotate
  class Renderer
    TEMPLATE_PATH = File.join(__dir__, 'logrotate.erb')

    def initialize(config)
      @config = config
    end

    # logrotate 設定ファイルをレンダリングしてファイルに出力する
    #
    # @param file_path [String] 出力先ファイルパス
    def render(file_path:)
      ErbWriter.new(TEMPLATE_PATH, @config).write_to_file(file_path)
    end
  end
end
