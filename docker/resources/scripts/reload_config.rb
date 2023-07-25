#!/usr/bin/ruby

require 'erb'

def log(*messages, **h)
  a = []
  messages.each do |msg|
    a << msg
  end
  h.each do |k, v|
    next unless v
    a << "#{k}=#{v}"
  end
  puts a.join(' ')
end

def shell_exec(*cmd)
  cmd_line = cmd.join(' ')
  log('SHELL_EXEC:', cmd_line)
  `#{cmd_line}`
  exit_status = $?.exitstatus
  if exit_status != 0
    raise "## ERROR ## exit status: #{exit_status} command_line: '#{cmd_line}'"
  end
  exit_status
end

class LetsEncrypt
  SETUP_LETSENCRIPT_SCRIPT = '/var/scripts/setup_letsencrypt.sh'

  def self.setup(config)
    shell_exec "APP_DOMAIN=#{config.domain}", "LETS_ENCRYPT_CERT_MAIL=#{config.cert_email}", SETUP_LETSENCRIPT_SCRIPT
  end
end

def normalize_name(name)
  name.gsub(/[\.\W]/, '_')
end

class Upstream
  attr_reader :name, :dest, :from_ips, :grpc

  def initialize(domain, dest, from_ips = nil, grpc = nil)
    @@index ||= 0
    @@index += 1
    @name = "#{normalize_name domain}-#{@@index}"
    @dest = [dest].flatten
    if from_ips && from_ips.to_s != 'all'
      @from_ips = [from_ips].flatten
    end
    @grpc = grpc
  end

  def proxy_to; @dest; end

  def check
    _check_array :proxy_to
    if from_ips
      _check_array :from_ips
      from_ips.each { |ip| _check_ip ip }
    end
  end

  private

  REGEXP_IP_ADDR = %r`^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)?$`
  def _check_ip(ip)
    mr = REGEXP_IP_ADDR.match ip 
    raise "invalid ip address '#{ip}'" unless mr
  end

  def _check_array(var_name)
    val = send var_name
    if !val.is_a?(Array) || val.length == 0
      raise "Array '#{var_name}' must has any elements!" 
    end
  end
end

class Redirect
  attr_reader :dest, :status

  def initialize(dest, status = 301)
    dest = "https://#{dest}" unless dest.start_with? 'http'
    dest = dest.chop if dest.end_with? '/'
    @dest = dest
    @status = status
  end

  def check
  end

  def to_s
    "return #{@status} #{@dest}$request_uri;"
  end
end

class ErbWriter
  def initialize(erb_file_path, config)
    @erb_file_path = erb_file_path
    @config = config
  end

  def output(io)
    erb = ERB.new(File.read @erb_file_path)
    result = erb.result_with_hash({config: @config})
    io.write(result)
  end

  def output_to_file(file_path)
    File.open(file_path, 'w') {|f| output f}
  end
end

class Config
  LOGROTATE_TEMPLATE_PATH = '/var/scripts/logrotate_template.erb'

  attr_accessor :domain, :locations, :current_location, :logrotate_generation, :logrotate_timing, :upstream_log, :no_ssl

  def initialize
    @curent_location = nil
    @locations = { }
    @nginx_configs = { }
  end

  def get_template_path(name)
    "/var/scripts/config_template_#{name}.erb"
  end

  def normalized_domain
    normalize_name domain
  end

  def add_upstream(destinations, from=nil, grpc: nil)
    l = @current_location || '/'
    _add_upstream l, normalized_domain, destinations, from, grpc
    log "CONFIG: Added Upstream.", domain: normalized_domain, dest: destinations, from_ips: from, in: l, grpc: grpc
  end

  def all_upstreams
    @locations.values.flatten
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
    ErbWriter.new(tp, self).output_to_file(file_path || output_path, 'w')
  end

  def output_logrotate_to_file(file_path = nil)
    # logrotate のデバッグ: /usr/sbin/logrotate -dv /etc/logrotate.conf
    ErbWriter.new(LOGROTATE_TEMPLATE_PATH, self).output_to_file(file_path || "/etc/logrotate.d/nginx_#{normalized_domain}", 'w')
  end

  # TODO: ネーミング再考
  def setup_ssl(force_update_cert = nil)
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
          shell_exec 'service nginx restart'
          sleep 2

          LetsEncrypt.setup self
          sleep 2
        end
      end

      output_to_file template: :https
    end
    shell_exec 'nginx -t'
    shell_exec 'service nginx reload'
    sleep 2

    output_logrotate_to_file unless %w/false 0 off no/.include? @logrotate.to_s.downcase
  end

  def check
    _check_required :domain
    if cert_file || key_file
      _check_file_exists :cert_file
      _check_file_exists :key_file
    else
      _check_required :cert_email
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
    raise "File not found! '#{var_name}'" unless File.exist? val
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

  def location(l)
    old = @config.current_location
    log "PARSER: Change location to '#{l}' from '#{old}'"
    @config.current_location = l
    yield if block_given?
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

  def self.parse(text)
    Parser.new.tap{ |p| p.instance_eval text }.results
  end

  def self.parse_file(file_path)
    raise "File not found. '#{file_path}'" unless File.exist? file_path
    self.parse File.read(file_path)
  end
end

# 環境変数やコンフィグファイルを解析してConfigインスタンスを返す
# @return [Array<Config>]
def get_config
  config_path = ENV['CONFIG_PATH']
  if config_path
    return Parser.parse_file config_path
  end

  proxy_to = ENV['PROXY_TO']
  if proxy_to
    domain, *list = proxy_to.split(',')
    c = Config.new
    c.domain = domain
    c.add_upstream list
    return [c]
  end
end

def backup_dir(path)
  path = path.chomp('/')
  path2 = "#{path}.bkup"
  if File.exist? path
    if File.exist? path2
      shell_exec 'rm', '-rf', path2
    end
    shell_exec 'mv', path, path2
  end
  Dir.mkdir path
  return unless block_given?
  begin
    yield
    flg = true
  ensure
    if !flg && !ENV['DEBUG'] && File.exist?(path2)
      shell_exec 'rm', '-rf', path
      shell_exec 'mv', path2, path
    end
  end
end


backup_dir(Config.output_dir) do
  configurations = get_config

  # check
  configurations.each do |config|
    config.check
  end

  # setup
  configurations.each do |config|
    log("----- start setup of Let's Encrypt for #{config.domain} -----")
    config.setup_ssl ENV['FORCE_MODE']
  end
  log("----- finish all setups successfully -----")
end

