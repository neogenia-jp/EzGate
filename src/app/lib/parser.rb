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

  def self.parse(text, file_path = nil)
    ps = new
    if file_path
      # 絶対パスに変換し、instance_eval の第２引数に渡す
      file_path = File.expand_path file_path
      ps.instance_eval text, file_path
    else
      ps.instance_eval text 
    end
    ps.results
  end

  def self.parse_file(file_path)
    raise "File not found. '#{file_path}'" unless File.exist? file_path
    self.parse File.read(file_path), file_path
  end
end
