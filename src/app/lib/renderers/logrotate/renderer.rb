# frozen_string_literal: true

require_relative '../base_renderer'

module Logrotate
  class Renderer < BaseRenderer
    TEMPLATE_PATH = File.join(__dir__, 'logrotate.erb')

    # logrotate 設定ファイルをレンダリングしてファイルに出力する
    #
    # @override
    # @param output_path [String] 出力先ファイルパス
    def render(output_path:)
      super template_path: TEMPLATE_PATH, output_path:
    end
  end
end
