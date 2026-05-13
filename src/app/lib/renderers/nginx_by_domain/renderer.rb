# frozen_string_literal: true

require_relative '../base_renderer'

module NginxByDomain
  class Renderer < BaseRenderer
    TEMPLATE_DIR = __dir__

    # nginx ドメイン設定ファイルをレンダリングしてファイルに出力する
    #
    # @override
    # @param template [Symbol] テンプレート名 (:http, :https, :cert)
    # @param output_path [String] 出力先ファイルパス
    def render(template:, output_path:)
      template_path = File.join(TEMPLATE_DIR, "#{template}.erb")
      super template_path:, output_path:
    end
  end
end
