# frozen_string_literal: true

require_relative '../test_helper'
require 'tempfile'
require 'lib/renderers/nginx_main/renderer'

class NginxMainRendererTest < Minitest::Test
  def setup
    @tmpfile = Tempfile.new('nginx_main_renderer_test')
  end

  def teardown
    @tmpfile.close
    @tmpfile.unlink
  end

  def test_デフォルト値でレンダリングできること
    NginxMain::Renderer.new.render(output_path: @tmpfile.path)
    content = File.read(@tmpfile.path)
    assert_includes content, 'worker_connections  8192'
    assert_includes content, 'multi_accept        off'
    assert_includes content, 'keepalive_timeout 65'
    assert_includes content, 'proxy_send_timeout 120'
    assert_includes content, 'proxy_read_timeout 120'
  end

  def test_環境変数でworker_connectionsを変更できること
    ENV['NGINX_WORKER_CONNECTIONS'] = '4096'
    NginxMain::Renderer.new.render(output_path: @tmpfile.path)
    content = File.read(@tmpfile.path)
    assert_includes content, 'worker_connections  4096'
  ensure
    ENV.delete 'NGINX_WORKER_CONNECTIONS'
  end

  def test_環境変数でmulti_acceptを変更できること
    ENV['NGINX_MULTI_ACCEPT'] = 'on'
    NginxMain::Renderer.new.render(output_path: @tmpfile.path)
    content = File.read(@tmpfile.path)
    assert_includes content, 'multi_accept        on'
  ensure
    ENV.delete 'NGINX_MULTI_ACCEPT'
  end

  def test_環境変数でkeepalive_timeoutを変更できること
    ENV['NGINX_KEEPALIVE_TIMEOUT'] = '30'
    NginxMain::Renderer.new.render(output_path: @tmpfile.path)
    content = File.read(@tmpfile.path)
    assert_includes content, 'keepalive_timeout 30'
  ensure
    ENV.delete 'NGINX_KEEPALIVE_TIMEOUT'
  end

  def test_環境変数でproxy_send_timeoutを変更できること
    ENV['NGINX_PROXY_SEND_TIMEOUT'] = '60'
    NginxMain::Renderer.new.render(output_path: @tmpfile.path)
    content = File.read(@tmpfile.path)
    assert_includes content, 'proxy_send_timeout 60'
  ensure
    ENV.delete 'NGINX_PROXY_SEND_TIMEOUT'
  end

  def test_環境変数でproxy_read_timeoutを変更できること
    ENV['NGINX_PROXY_READ_TIMEOUT'] = '60'
    NginxMain::Renderer.new.render(output_path: @tmpfile.path)
    content = File.read(@tmpfile.path)
    assert_includes content, 'proxy_read_timeout 60'
  ensure
    ENV.delete 'NGINX_PROXY_READ_TIMEOUT'
  end
end
