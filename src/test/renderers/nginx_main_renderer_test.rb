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
  end

  def test_環境変数でworker_connectionsを変更できること
    ENV['NGINX_WORKER_CONNECTIONS'] = '4096'
    NginxMain::Renderer.new.render(output_path: @tmpfile.path)
    content = File.read(@tmpfile.path)
    assert_includes content, 'worker_connections  4096'
  ensure
    ENV.delete 'NGINX_WORKER_CONNECTIONS'
  end
end
