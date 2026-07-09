# frozen_string_literal: true

require_relative 'evaluator'

module Dsl
  class Loader
    # 設定ファイルを読み込んで ConfigContext インスタンスの配列を返す
    # @param file_path [String] 設定ファイルのパス
    # @return [Array<ConfigContext>]
    def self.load(file_path)
      instance = new
      instance.include_file file_path
      results = instance.context.results
      
      # グローバル nginx_config を各 ConfigContext にセット
      global_configs = instance.context.global_nginx_configs
      results.each do |config|
        config.global_nginx_configs = global_configs
      end
      
      results
    end

    def initialize
      @context = Evaluator.new
    end

    def context
      @context
    end

    def include_file(file_path)
      @context.include_file file_path
    end
  end
end
