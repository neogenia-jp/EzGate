# frozen_string_literal: true

require_relative '../../erb_writer'

module NginxByDomain
  class Renderer
    TEMPLATE_DIR = __dir__

    def initialize(config)
      @config = config
    end

    # nginx ドメイン設定ファイルをレンダリングしてファイルに出力する
    #
    # @param template [Symbol] テンプレート名 (:http, :https, :cert)
    # @param file_path [String] 出力先ファイルパス
    def render(template:, file_path:)
      tp = File.join(TEMPLATE_DIR, "#{template}.erb")
      ErbWriter.new(tp, @config).write_to_file(file_path)
    end
  end
end
