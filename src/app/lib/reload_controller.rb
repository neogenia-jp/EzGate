#!/usr/bin/ruby
# frozen_string_literal: true

require_relative './functions'
require_relative './parser'
require_relative './config'
require_relative './socat_manager'

class ReloadController

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

  def exec
    backup_dir(Config.output_dir) do
      _exec
    end
  end

  def _exec
      configurations = get_config
      raise 'no configurations. please set $CONFIG_PATH or $PROXY_TO env var.' unless configurations

      # check
      configurations.each do |config|
        config.check
      end

      SocatManager.instance.ensure_process do
        _exec_core configurations
    end
  end

  def _exec_core(configurations)
    # NOTE: SSL セットアップが必要なものを最後に処理する。
    # そうしないと、Let's Encryptセットアップのために nginx をリロードした際に、
    # まだ config が書き出されていないがドメインがアクセスエラーになる。
    grouped = configurations.group_by{|x| x.ssl_setup_priority}
    grouped.keys.sort.each do |type|
      configs = grouped[type]
      log "========== #{type} =========="
      configs.each do |config|
        log "----- #{config.domain} -----"
        config.generate_nginx_config
      end
    end

    # FORCE_MODE であれば、 2:installed なドメインについて Let's Encrypt のセットアップを再実行する
    # 一回目のループでやらない理由は、2:installed なドメインが複数ある時に、
    # まだ config が書き出されていないドメインがアクセスエラーになるのを防ぐため。
    # したがって一回目のループで一通り config を書き出した後に、再実行する必要がある。
    type = "2:installed"
    if ENV['FORCE_MODE'] && grouped[type]&.any?
      log "========== #{type} FORCE re-install =========="
      grouped[type].each do |config|
        log "----- #{config.domain} (FORCE) -----"
        config.generate_nginx_config force_update_cert: true
      end
    end
    log "----- finish all setups successfully -----"

    shell_exec 'nginx -s reload'
  end
end
