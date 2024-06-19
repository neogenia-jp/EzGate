# frozen_string_literal: true

require_relative 'test_helper'
require 'lib/domain_util'

class DomainUtilTest < Minitest::Test
  def test_normalize_name
    result = DomainUtil.normalize_name 'aaa.example.com'
    assert_equal 'aaa_example_com', result

    result = DomainUtil.normalize_name 'abc-ABC.012@xxx:yyy#zzz'
    assert_equal 'abc_ABC_012_xxx_yyy_zzz', result
    
    str = %/!"#$%&'()-^=~@`[]{};:+*,.<>?\/_\\/
    result = DomainUtil.normalize_name str
    assert_equal str.length, result.length
    assert_equal '_'*str.length, result
  end
end
