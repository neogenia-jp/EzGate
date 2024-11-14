# frozen_string_literal: true
require_relative 'functions'
require_relative 'config'

class Parser
  def initialize
    @hash = {}
  end

  # @return [Array<Config>]
  def results
    @hash.values
  end

  def domain(name)
    @config = (@hash[name] ||= Config.new)
    @config.domain = name
    log "PARSER: detect domain(#{name})"
    yield if block_given?
  end

  # 現在の location を変更してブロックを実行する
  # @param l [String] nginx の location ディレクティブに指定する文字列
  def location(l, &proc)
    old = @config.current_location
    log "PARSER: Change location to '#{l}' from '#{old}'"
    @config.current_location = l
    proc.call
    @config.current_location = old
  end

  def proxy_to(*destinations, from: :all)
    log "PARSER: detect proxy_to(#{destinations}, from: #{from})"
    @config.add_upstream destinations, from
  end

  def grpc_to(*destinations, from: :all)
    log "PARSER: detect grpc_to(#{destinations}, from: #{from})"
    @config.add_upstream destinations, from, grpc: true
  end

  def redirect_to(destination, status: 301)
    log "PARSER: detect redirect_to(#{destination}, status: #{status})"
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
    # raise "adapter parameter '#{options}' not supported." if options != 'socat'
    log "PARSER: detect adapter(#{options})"
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

  def include_file(file_path)
    # 絶対パスに変換
    file_path = if @current_parse_file
                  # 現在パース中のファイルがあれば、そこを基準にパス展開する
                  File.expand_path file_path, File.dirname(@current_parse_file)
                else
                  File.expand_path file_path
                end
    # ファイル存在チェック
    raise "File not found. '#{file_path}'" unless File.exist? file_path

    # 現在パース中のファイルを順繰り
    bkup = @current_parse_file
    @current_parse_file = file_path
    
    begin
      self.instance_eval File.read(file_path), file_path
    ensure
      @current_parse_file = bkup
    end
  end

  def self.parse_file(file_path)
    instance = new
    instance.include_file file_path
    instance.results
  end
end
