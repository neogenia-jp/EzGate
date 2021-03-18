#!/usr/bin/ruby

require 'erb'

def log(*messages)
  messages.each do |msg|
    print msg
    print ' '
  end
  puts
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
  attr_reader :name, :dest, :from_ips

  def initialize(domain, dest, from_ips = nil)
    @@index ||= 0
    @@index += 1
    log "CONFIG: Upstream[#{@@index}] domain=#{domain} dest=#{dest} from_ips=#{from_ips}"
    @name = "#{normalize_name domain}-#{@@index}"
    @dest = [dest].flatten
    if from_ips && from_ips.to_s != 'all'
      @from_ips = [from_ips].flatten
    end
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

class Config
  TEMPLATE_PATH = '/var/scripts/config_template.erb'

  attr_accessor :domain, :upstreams, :nginx_config
  attr_reader :enable_ssl

  def initialize
    @enable_ssl = false
    @upstreams = []
  end

  def normalized_domain
    normalize_name domain
  end

  def add_upstream(destinations, from=nil)
    @upstreams << Upstream.new(normalized_domain, destinations, from)
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

  def output(io)
    erb = ERB.new(File.read TEMPLATE_PATH)
    result = erb.result_with_hash({config: self})
    io.write(result)
  end

  def output_to_file(file_path = nil)
    File.open(file_path || output_path, 'w') {|f| output f}
  end

  def setup_ssl(force=nil)
    unless cert_file
      if force || !File.exist?("/etc/letsencrypt/live/#{domain}")
        output_to_file
        shell_exec 'nginx -t'
        shell_exec 'service nginx restart'
        sleep 2

        LetsEncrypt.setup self
        sleep 2
      end
    end

    @enable_ssl = true
    output_to_file
    shell_exec 'nginx -t'
    shell_exec 'service nginx reload'
    sleep 2
  end

  def check
    _check_required :domain
    if cert_file || key_file
      _check_file_exists :cert_file
      _check_file_exists :key_file
    else
      _check_required :cert_email
    end

    upstreams.each { |u| u.check }
    _check_and_reorder_upstreams(upstreams)
  end

  private
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

  def _check_and_reorder_upstreams(upstreams)
    defaults = upstreams.reject(&:from_ips)
    if defaults.empty?
      warn "*** WARN: No relay destinations defined for '#{domain}'."
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

  def results
    @hash.values
  end

  def domain(name)
    @config = (@hash[name] ||= Config.new)
    @config.domain = name
    yield if block_given?
  end

  def proxy_to(*destinations, from: :all)
    @config.add_upstream destinations, from
  end

  def nginx_config(config_text)
    @config.nginx_config = config_text
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

  def self.parse(text)
    Parser.new.tap{ |p| p.instance_eval text }.results
  end

  def self.parse_file(file_path)
    raise "File not found. '#{file_path}'" unless File.exist? file_path
    self.parse File.read(file_path)
  end
end

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

