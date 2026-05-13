# frozen_string_literal: true

require_relative '../test_helper'
require 'tempfile'
require 'lib/config'
require 'lib/renderers/logrotate/renderer'

class LogrotateRendererTest < Minitest::Test
  def setup
    @config = Config.new
    @config.domain = 'test.example.com'
    @tmpfile = Tempfile.new('logrotate_renderer_test')
  end

  def teardown
    @tmpfile.close
    @tmpfile.unlink
  end

  def test_デフォルト設定でレンダリングできること
    Logrotate::Renderer.new(@config).render(output_path: @tmpfile.path)
    content = File.read(@tmpfile.path)
    assert_includes content, '/var/log/nginx/error_test_example_com.log'
    assert_includes content, '/var/log/nginx/access_test_example_com.log'
    assert_includes content, 'daily'
    assert_includes content, 'rotate 60'
  end

  def test_ローテーション設定が反映されること
    @config.logrotate_generation = 10
    @config.logrotate_timing = :weekly
    Logrotate::Renderer.new(@config).render(output_path: @tmpfile.path)
    content = File.read(@tmpfile.path)
    assert_includes content, 'weekly'
    assert_includes content, 'rotate 10'
  end
end
