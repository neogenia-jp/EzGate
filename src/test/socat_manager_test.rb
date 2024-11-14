# frozen_string_literal: true

require_relative 'test_helper'
require 'lib/socat_manager'

class SocatManagerTest < Minitest::Test
  def setup
    @svc = SocatManager.instance
  end

  def teardown
    #@svc&.send :_cleanup
  end

  def test_registerしていくとrunningが増え、_cleanupで指定したもの以外は終了されること
    result = @svc.register('192.168.1.102:8082')
    puts result

    result = @svc.send :_running?, '192.168.1.102:8082'
    assert result
    result = @svc.send :_running?, '192.168.1.103:8083'
    assert_nil result  # 起動していない

    result = @svc.register('192.168.1.103:8083')
    puts result

    result = @svc.send :_running?, '192.168.1.102:8082'
    assert result
    result = @svc.send :_running?, '192.168.1.103:8083'
    assert result  # 起動している

    @svc.send :_cleanup, '192.168.1.103:8083'

    result = @svc.send :_running?, '192.168.1.102:8082'
    assert_nil result  # 起動していない
    result = @svc.send :_running?, '192.168.1.103:8083'
    assert result
  end

end
