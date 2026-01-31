#!/usr/bin/ruby
# frozen_string_literal: true

require_relative 'lib/functions'
require_relative 'lib/parser'
require_relative 'lib/config'
require_relative 'lib/socat_manager'

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
  raise 'no configurations. please set $CONFIG_PATH or $PROXY_TO env var.' unless configurations

  # check
  configurations.each do |config|
    config.check
  end

  SocatManager.instance.ensure_process do
    # setup
    configurations.each do |config|
      log "----- start setup of Let's Encrypt for #{config.domain} -----"
      config.setup_ssl ENV['FORCE_MODE']
    end
    log "----- finish all setups successfully -----"
  end

  shell_exec 'service nginx reload'
end

