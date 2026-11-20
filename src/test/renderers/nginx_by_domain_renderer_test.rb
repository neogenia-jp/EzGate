# frozen_string_literal: true

require_relative '../test_helper'
require 'tempfile'
require 'lib/config_context'
require 'lib/renderers/nginx_by_domain/renderer'

class NginxByDomainRendererTest < Minitest::Test
  def setup
    @config = ConfigContext.new
    @config.domain = 'test.example.com'
    @config.no_ssl = true
    @tmpfile = Tempfile.new('nginx_by_domain_renderer_test')
  end

  def teardown
    @tmpfile.close
    @tmpfile.unlink
  end

  def test_httpテンプレートでレンダリングできること
    NginxByDomain::Renderer.new(@config).render(template: :http, output_path: @tmpfile.path)
    content = File.read(@tmpfile.path)
    assert_includes content, 'server_name  test.example.com'
    assert_includes content, 'listen       80'
  end

  def test_httpsテンプレートでレンダリングできること
    @config.cert_file = '/mnt/cert.pem'
    @config.key_file  = '/mnt/key.pem'
    NginxByDomain::Renderer.new(@config).render(template: :https, output_path: @tmpfile.path)
    content = File.read(@tmpfile.path)
    assert_includes content, 'server_name  test.example.com'
    assert_includes content, 'listen       443 ssl http2'
    assert_includes content, '/mnt/cert.pem'
    assert_includes content, '/mnt/key.pem'
  end

  def test_環境変数HTTP2でhttp2を無効化できること
    @config.cert_file = '/mnt/cert.pem'
    @config.key_file  = '/mnt/key.pem'
    %w/false 0 off no OFF/.each do |v|
      with_env('HTTP2' => v) do
        NginxByDomain::Renderer.new(@config).render(template: :https, output_path: @tmpfile.path)
      end
      content = File.read(@tmpfile.path)
      assert_includes content, 'listen       443 ssl '
      refute_includes content, 'http2', "HTTP2=#{v}"
    end
  end

  def test_環境変数HTTP2が未指定または有効値ならhttp2が有効なこと
    @config.cert_file = '/mnt/cert.pem'
    @config.key_file  = '/mnt/key.pem'
    [nil, '', 'true', 'on', '1'].each do |v|
      with_env('HTTP2' => v) do
        NginxByDomain::Renderer.new(@config).render(template: :https, output_path: @tmpfile.path)
      end
      assert_includes File.read(@tmpfile.path), 'listen       443 ssl http2', "HTTP2=#{v.inspect}"
    end
  end

  def with_env(vars)
    old = vars.keys.to_h { |k| [k, ENV[k]] }
    vars.each { |k, v| ENV[k] = v }
    yield
  ensure
    old.each { |k, v| ENV[k] = v }
  end

  def test_certテンプレートでレンダリングできること
    NginxByDomain::Renderer.new(@config).render(template: :cert, output_path: @tmpfile.path)
    content = File.read(@tmpfile.path)
    assert_includes content, 'server_name  test.example.com'
    assert_includes content, 'listen       80'
    assert_includes content, '.well-known/acme-challenge'
  end
end
