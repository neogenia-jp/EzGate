# frozen_string_literal: true

require_relative 'test_helper'
require 'lib/parser'

class ParserTest < Minitest::Test
  def setup
    @parser = Parser.new
  end

  def test_domain_ブロックの戻り値がメソッドの戻り値になっていること
    result = @parser.domain('aaa.example.com') do
      10
    end
    assert_equal 10, result

    result = @parser.domain('aaa.example.com') do
      nil
    end
    assert_nil result

    result = @parser.domain('aaa.example.com') do
    end
    assert_nil result
  end

  def test_domainを呼ぶたびにresultsにドメインが追加されること
    assert_equal 0, @parser.results.length

    @parser.domain('aaa.example.com') do
    end
    
    # results にドメインが入っていること
    assert_equal 1, @parser.results.length
    assert_instance_of Config, @parser.results[0]
    assert_equal 'aaa.example.com', @parser.results[0].domain

    @parser.domain('bbb.example.com') do
    end

    # result にドメインが追加されていること
    assert_equal 2, @parser.results.length
    assert_instance_of Config, @parser.results[0]
    assert_equal 'aaa.example.com', @parser.results[0].domain
    assert_instance_of Config, @parser.results[1]
    assert_equal 'bbb.example.com', @parser.results[1].domain
  end

  def test_基本的なDSLがConfigインスタンスに反映されることの検証
    results = Parser.parse_file File.expand_path('test_config_files/test1_basic.conf.rb', __dir__)
    
    # result にドメインが追加されていること
    assert_equal 2, results.length

    config = results[0]
    assert_instance_of Config, config
    assert_equal 'test1.example.com', config.domain
    assert_equal 'socat', config.adapter
    assert_equal 'w.maeda@neogenia.co.jp', config.cert_email
    assert_equal '/mnt/cert.pem', config.cert_file
    assert_equal '/mnt/key.pem', config.key_file
    assert_equal 5, config.logrotate_generation
    assert_equal :weekly, config.logrotate_timing
    assert_equal true, config.upstream_log
    assert_equal true, config.no_ssl
    
    # location の検証
    assert_equal 2, config.locations.length
    assert_equal ['/', '/map_api'], config.locations.keys

    loc = config.locations['/']
    assert_equal 1, loc.length
    assert_instance_of Upstream, loc.first
    assert_equal ['webapp1'], loc.first.dest
    assert_nil loc.first.grpc
    
    loc = config.locations['/map_api']
    assert_equal 1, loc.length
    assert_instance_of Upstream, loc.first
    assert_equal ['webapp2'], loc.first.dest
    assert_nil loc.first.grpc

    config = results[1]
    assert_instance_of Config, config
    assert_equal 'test2.example.com', config.domain
    assert_nil config.adapter
    assert_nil config.cert_email
    assert_nil config.cert_file
    assert_nil config.key_file
    assert_equal 7, config.logrotate_generation
    assert_nil config.logrotate_timing
    assert_nil config.upstream_log
    assert_equal <<~TEXT, config.get_nginx_config
      proxy_http_version 1.1;

      location / {
        return 301   https://test3.example.com$request_uri;
      }
    TEXT
  end

  def test_CERT_EMAIL_は環境変数が定義されていればそちらが優先されること
    #: TODO
  end
  
  def test_CERT_FILE_は環境変数が定義されていればそちらが優先されること
    #: TODO
  end

  def test_KEY_FILE_は環境変数が定義されていればそちらが優先されること
    #: TODO
  end

  def test_GRPCのDSLの検証
    results = Parser.parse_file File.expand_path('test_config_files/test2_grpc.conf.rb', __dir__)
    
    assert_equal 1, results.length

    config = results[0]
    assert_instance_of Config, config
    assert_equal '192.168.1.101.nip.io', config.domain
    assert_nil config.adapter
    assert_nil config.cert_email
    assert_nil config.cert_file
    assert_nil config.key_file
    assert_nil config.logrotate_generation
    assert_nil config.logrotate_timing
    assert_nil config.upstream_log
    assert_nil config.no_ssl
    
    # location の検証
    assert_equal 2, config.locations.length
    assert_equal ['/', '= /error502grpc'], config.locations.keys

    loc = config.locations['/']
    assert_equal 1, loc.length
    assert_instance_of Upstream, loc.first
    assert_equal ['grpc_server1:50051', 'grpc_server2:50051'], loc.first.dest
    assert_equal true, loc.first.grpc
    
    assert_equal <<~TEXT, config.get_nginx_config
      ssl_verify_client off;           # [Optional] Do not check client SSL certificates
      error_page 502 = /error502grpc;
    TEXT

    loc = config.locations['= /error502grpc']
    assert_equal 0, loc.length  # Upstream なし

    assert_equal <<~TEXT, config.get_nginx_config('= /error502grpc')
      internal;
      default_type application/grpc;
      add_header grpc-status 14;
      add_header grpc-message "unavailable all upstreams!";
      return 204;
    TEXT
  end

  def test_listen_optionsのDSLがConfigインスタンスに反映されることの検証
    results = Parser.parse_file File.expand_path('test_config_files/test3_listen_options.conf.rb', __dir__)
    
    assert_equal 2, results.length

    config = results[0]
    assert_instance_of Config, config
    assert_equal 'test3-1.example.com', config.domain
    assert_equal 'so_keepalive=on', config.listen_options
    assert_nil config.adapter
    assert_nil config.cert_email
    assert_nil config.cert_file
    assert_nil config.key_file
    assert_nil config.logrotate_generation
    assert_nil config.logrotate_timing
    assert_nil config.upstream_log
    assert_nil config.no_ssl

    config = results[1]
    assert_instance_of Config, config
    assert_equal 'test3-2.example.com', config.domain
    assert_equal 'so_keepalive=on deferred rcvbuf=8192', config.listen_options
  end

end
