# frozen_string_literal: true
require_relative 'functions'
require_relative 'upstream'
require_relative 'redirect'
require_relative 'erb_writer'
require_relative 'lets_encrypt'
require_relative 'domain_util'

class Config
  LOGROTATE_TEMPLATE_PATH = '/var/scripts/app/logrotate_template.erb'

  attr_accessor :domain, :locations, :current_location, :logrotate_generation, :logrotate_timing, :upstream_log, :no_ssl, :adapter

  def initialize
    @current_location = nil
    @locations = { }
    @nginx_configs = { }
  end

  def get_template_path(name)
    "/var/scripts/app/config_template_#{name}.erb"
  end

  def normalized_domain
    DomainUtil.normalize_name domain
  end

  def add_upstream(destinations, from=nil, grpc: nil)
    l = @current_location || '/'
    _add_upstream l, normalized_domain, destinations, from, grpc
    log "CONFIG: Added Upstream.", domain: normalized_domain, dest: destinations, from_ips: from, in: l, grpc: grpc
  end

  # @return [Array<Upstream>]
  def all_upstreams
    a = @locations.values.flatten
    case @adapter.to_s.downcase
    when 'socat'
      a.each {|x| x.socat = true }
    when nil, '', 'none', 'direct'
      # do nothing
    else
      raise "Unknown adapter: #{@adapter}"
    end
    a
  end

  def add_redirect(destination, status=301)
    l = @current_location || '/'
    _add_upstream l   # locations も作っておく必要あり
    (@nginx_configs[l] ||= []) << Redirect.new(destination, status)
    log "CONFIG: Added Redirect.", domain: normalized_domain, dest: destination, status: status, in: l
  end

  def all_redirect(location = nil)
    a = @nginx_configs[location]
    a&.select{|x| x.is_a? Redirect}
  end

  def add_nginx_config(config_text)
    l = @current_location || ''
    if !l.empty?
      _add_upstream l   # locations も作っておく必要あり
    end
    (@nginx_configs[l] ||= []) << config_text
    log "CONFIG: Added nginx_config in '#{l}'"
  end

  def get_nginx_config(location = '')
    @nginx_configs[location]&.flatten&.join("\n")
  end

  def cert_email=(mail_address)
    @cert_email = mail_address
  end

  def cert_email
    ENV['CERT_EMAIL'] || @cert_email
  end

  def cert_file=(file_path)
    @cert_file = file_path
  end

  def cert_file
    ENV['CERT_FILE'] || @cert_file
  end

  def key_file=(file_path)
    @key_file = file_path
  end

  def key_file
    ENV['KEY_FILE'] || @key_file
  end

  def self.output_dir
    '/etc/nginx/sites-enabled/'
  end

  def output_path
    @output_path ||= "#{self.class.output_dir}#{normalized_domain}"
  end

  def output_to_file(file_path = nil, template: )
    tp = get_template_path template
    ErbWriter.new(tp, self).write_to_file(file_path || output_path)
  end

  def output_logrotate_to_file(file_path = nil)
    # logrotate のデバッグ: /usr/sbin/logrotate -dv /etc/logrotate.conf
    ErbWriter.new(LOGROTATE_TEMPLATE_PATH, self).write_to_file(file_path || "/etc/logrotate.d/nginx_#{normalized_domain}")
  end

  # nginx設定ファイルを生成して出力する
  #
  # このメソッドは以下の処理を実行します：
  # 1. SSL設定の有無に応じて適切なnginxテンプレートを選択
  # 2. HTTPS対応かつ証明書が指定されていない場合、Let's Encryptで自動証明書化
  # 3. nginx設定ファイルを出力
  # 4. ログローテーション設定ファイルを出力
  # 5. nginx設定の構文チェック
  #
  # @param force_update_cert [Boolean] trueの場合、既存の証明書を無視して再生成
  def generate_nginx_config(force_update_cert = nil)
    if @no_ssl
      # HTTPS 非対応
      output_to_file template: :http
    else
      # HTTPS 対応版
      unless cert_file
        # 証明書ファイルが指定されていなければ、Let's Encrypt を使って生成する
        if force_update_cert || !File.exist?("/etc/letsencrypt/live/#{domain}")
          output_to_file template: :cert
          shell_exec 'nginx -t'

          LetsEncrypt.setup self
        end
      end

      output_to_file template: :https
    end
    shell_exec 'nginx -t'

    output_logrotate_to_file unless %w/false 0 off no/.include? @logrotate.to_s.downcase
  end

  def check
    _check_required :domain
    unless @no_ssl
      # HTTPS 対応にする場合
      if cert_file || key_file
        # cert, key が指定されていれば存在チェック
        _check_file_exists :cert_file
        _check_file_exists :key_file
      else
        # 指定されていなかったら Let's Encrypt で証明書発行するのでメールアドレスが必要
        _check_required :cert_email
      end
    end

    all_upstreams.each { |u| u.check }

    locations.each do |loc, upstreams|
      a = all_redirect(loc) || []
      if a.length >= 2
        raise "Multiple 'redirect_to' statements are not supported (in '#{loc}' of '#{domain}')."
      end
      if _check_and_reorder_upstreams(upstreams, loc) == 0
        warn "*** WARN: No relay destinations defined for '#{domain}'." if a.length == 0
      else
        raise "'proxy_to' and 'redirect_to' cannot be specified at the same time. (in '#{loc}' of '#{domain}')." if a.length >= 1
      end
    end
    # The key is nil to last
    val = locations.delete('/')
    locations['/'] = val if val
  end

  private
  def _add_upstream(location, *upstream_params)
    l = @locations[location] ||= []
    if upstream_params.length > 0
      l << Upstream.new(*upstream_params)
    end

    # 特異メソッドを追加
    if !l.respond_to?(:grpc?)
      def l.grpc?
        self.first&.grpc
      end
    end
  end

  def _check_required(var_name)
    val = "#{self.send(var_name)}".strip
    raise "Parameter '#{var_name}' is not defined!" if val == ''
    val
  end

  def _check_file_exists(var_name)
    val = _check_required var_name
    raise "File not found! path='#{val}' specified by '#{var_name}'" unless File.exist? val
    val
  end

  def _check_and_reorder_upstreams(upstreams, loc)
    defaults = upstreams.reject(&:from_ips)
    if defaults.empty?
      return 0
    end
    raise "Multiple default destinations are defined: #{defaults.map{|u| "'#{u.dest}'"}.join(', ')}" if defaults.count > 1
    # reorder
    upstreams.delete defaults.first
    upstreams << defaults.first
    true
  end
end
