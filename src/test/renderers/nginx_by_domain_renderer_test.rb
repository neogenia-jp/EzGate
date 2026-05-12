# frozen_string_literal: true

require_relative '../test_helper'
require 'tempfile'
require 'lib/config'
require 'lib/renderers/nginx_by_domain/renderer'

class NginxByDomainRendererTest < Minitest::Test
  def setup
    @config = Config.new
    @config.domain = 'test.example.com'
    @config.no_ssl = true
    @tmpfile = Tempfile.new('nginx_by_domain_renderer_test')
  end

  def teardown
    @tmpfile.close
    @tmpfile.unlink
  end

  def test_httpテンプレートでレンダリングできること
    NginxByDomain::Renderer.new(@config).render(template: :http, file_path: @tmpfile.path)
    content = File.read(@tmpfile.path)
    assert_includes content, 'server_name  test.example.com'
    assert_includes content, 'listen       80'
  end

  def test_httpsテンプレートでレンダリングできること
    @config.cert_file = '/mnt/cert.pem'
    @config.key_file  = '/mnt/key.pem'
    NginxByDomain::Renderer.new(@config).render(template: :https, file_path: @tmpfile.path)
    content = File.read(@tmpfile.path)
    assert_includes content, 'server_name  test.example.com'
    assert_includes content, 'listen       443 ssl http2'
    assert_includes content, '/mnt/cert.pem'
    assert_includes content, '/mnt/key.pem'
  end

  def test_certテンプレートでレンダリングできること
    NginxByDomain::Renderer.new(@config).render(template: :cert, file_path: @tmpfile.path)
    content = File.read(@tmpfile.path)
    assert_includes content, 'server_name  test.example.com'
    assert_includes content, 'listen       80'
    assert_includes content, '.well-known/acme-challenge'
  end
end
