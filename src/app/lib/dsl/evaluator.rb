# frozen_string_literal: true

require_relative '../functions'
require_relative '../config_context'

module Dsl
  class Evaluator
    def initialize
      @hash = {}
    end

    # @return [Array<ConfigContext>]
    def results
      @hash.values
    end

    def domain(name)
      @config = (@hash[name] ||= ConfigContext.new)
      @config.domain = name
      log "DSL: detect domain(#{name})"
      yield if block_given?
    end

    # listen の後ろに追加する文字列を指定する
    # @see https://nginx.org/en/docs/http/ngx_http_core_module.html#listen
    def listen_options(*opts)
      @config.listen_options = opts
    end

    # 現在の location を変更してブロックを実行する
    # @param l [String] nginx の location ディレクティブに指定する文字列
    def location(l, &proc)
      old = @config.current_location
      log "DSL: Change location to '#{l}' from '#{old}'"
      @config.current_location = l
      proc.call
      @config.current_location = old
    end

    def proxy_to(*destinations, from: :all)
      log "DSL: detect proxy_to(#{destinations}, from: #{from})"
      @config.add_upstream destinations, from
    end

    def grpc_to(*destinations, from: :all)
      log "DSL: detect grpc_to(#{destinations}, from: #{from})"
      @config.add_upstream destinations, from, grpc: true
    end

    def redirect_to(destination, status: 301)
      log "DSL: detect redirect_to(#{destination}, status: #{status})"
      @config.add_redirect destination, status
    end

    def nginx_config(config_text)
      @config.add_nginx_config config_text
    end

    def no_ssl
      @config.no_ssl = true
    end

    def adapter(options='socat')
      options = options.to_s
      log "DSL: detect adapter(#{options})"
      @config.adapter = options
    end

    def cert_email(mail_address)
      @config.cert_email = mail_address
    end

    def cert_file(file_path)
      @config.cert_file = file_path
    end

    def key_file(file_path)
      @config.key_file = file_path
    end

    def logrotate(generation, timing=nil)
      @config.logrotate_generation = generation
      @config.logrotate_timing = timing
    end

    def upstream_log(enabled = true)
      @config.upstream_log = enabled
    end
  end
end
