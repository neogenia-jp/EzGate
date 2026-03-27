# frozen_string_literal: true

require_relative 'test_helper'
require 'lib/reload_controller'

class ReloadControllerTest < Minitest::Test
  # generate_nginx_config の呼び出しを記録するモック Config
  class MockConfig
    attr_reader :domain, :generate_nginx_config_calls

    def initialize(domain, priority)
      @domain = domain
      @priority = priority
      @generate_nginx_config_calls = []
    end

    def ssl_setup_priority
      @priority
    end

    def generate_nginx_config(**opts)
      @generate_nginx_config_calls << opts
    end
  end

  def setup
    @controller = ReloadController.new
  end

  def test_exec_core_優先度ごとの実行順序になっていること
    config_need    = MockConfig.new("need-install.example.com", "3:need_install")
    config_no_ssl  = MockConfig.new("no-ssl.example.com",       "1:no_installation")
    config_installed = MockConfig.new("installed.example.com",  "2:installed")

    # 意図的に優先度の逆順で渡す
    configurations = [config_need, config_no_ssl, config_installed]

    call_order = []
    [config_no_ssl, config_installed, config_need].each do |c|
      c.define_singleton_method(:generate_nginx_config) do |**opts|
        call_order << domain
        @generate_nginx_config_calls << opts
      end
    end

    @controller.stub(:shell_exec, nil) do
      @controller._exec_core(configurations)
    end

    assert_equal(
      ["no-ssl.example.com", "installed.example.com", "need-install.example.com"],
      call_order,
      "generate_nginx_config が優先度昇順（1→2→3）で呼ばれること"
    )
  end

  def test_exec_core_FORCEモードの時は2_installedなドメインについて再実行されること
    config_no_ssl    = MockConfig.new("no-ssl.example.com",    "1:no_installation")
    config_installed = MockConfig.new("installed.example.com", "2:installed")
    configurations   = [config_no_ssl, config_installed]

    ENV['FORCE_MODE'] = '1'
    begin
      @controller.stub(:shell_exec, nil) do
        @controller._exec_core(configurations)
      end
    ensure
      ENV.delete('FORCE_MODE')
    end

    # 1:no_installation は通常の呼び出しのみ（force しない）
    assert_equal 1, config_no_ssl.generate_nginx_config_calls.length
    assert_equal({}, config_no_ssl.generate_nginx_config_calls.first)

    # 2:installed は通常の呼び出し + force_update_cert: true での再実行
    assert_equal 2, config_installed.generate_nginx_config_calls.length
    assert_equal({},                          config_installed.generate_nginx_config_calls[0])
    assert_equal({ force_update_cert: true }, config_installed.generate_nginx_config_calls[1])
  end
end
