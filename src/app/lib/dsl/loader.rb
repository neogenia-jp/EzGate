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
      # 絶対パスに変換
      file_path = if @current_file
                    # 現在パース中のファイルがあれば、そこを基準にパス展開する
                    File.expand_path file_path, File.dirname(@current_file)
                  else
                    File.expand_path file_path
                  end
      # ファイル存在チェック
      raise "File not found. '#{file_path}'" unless File.exist? file_path

      # 現在パース中のファイルを順繰り
      bkup = @current_file
      @current_file = file_path

      begin
        @context.instance_eval File.read(file_path), file_path
      ensure
        @current_file = bkup
      end
    end
  end
end
