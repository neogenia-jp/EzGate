# frozen_string_literal: true

require_relative '../base_renderer'

module NginxMain
  class Renderer < BaseRenderer
    TEMPLATE_PATH = File.join(__dir__, 'nginx.conf.erb')
    OUTPUT_PATH   = '/etc/nginx/nginx.conf'

    def initialize(config = nil)
      super(config)
    end

    # nginx.conf を指定パスにレンダリングして出力する（テスト用途）
    #
    # @override
    # @param output_path [String] 出力先ファイルパス
    def render(output_path: nil)
      super template_path: TEMPLATE_PATH, output_path: output_path || OUTPUT_PATH
    end
  end
end
