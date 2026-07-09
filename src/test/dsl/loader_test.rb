# frozen_string_literal: true

require_relative '../test_helper'
require 'lib/dsl/loader'
require 'lib/config_context'

class LoaderTest < Minitest::Test
  def setup
    @context = Dsl::Evaluator.new
  end

  def test_domainを呼ぶたびにresultsにドメインが追加されること
    assert_equal 0, @context.results.length

    @context.domain('aaa.example.com') do
    end
    
    # results にドメインが入っていること
    assert_equal 1, @context.results.length
    assert_instance_of ConfigContext, @context.results[0]
    assert_equal 'aaa.example.com', @context.results[0].domain

    @context.domain('bbb.example.com') do
    end

    # result にドメインが追加されていること
    assert_equal 2, @context.results.length
    assert_instance_of ConfigContext, @context.results[0]
    assert_equal 'aaa.example.com', @context.results[0].domain
    assert_instance_of ConfigContext, @context.results[1]
    assert_equal 'bbb.example.com', @context.results[1].domain
  end

  def test_domainに複数ドメインを指定するとresultsに全て追加されること
    @context.domain('aaa.example.com', 'bbb.example.com') do
    end

    assert_equal 2, @context.results.length
    assert_instance_of ConfigContext, @context.results[0]
    assert_equal 'aaa.example.com', @context.results[0].domain
    assert_instance_of ConfigContext, @context.results[1]
    assert_equal 'bbb.example.com', @context.results[1].domain
  end

  def test_domainに配列でドメインを指定できること
    @context.domain(['ccc.example.com', 'ddd.example.com']) do
    end

    assert_equal 2, @context.results.length
    assert_equal 'ccc.example.com', @context.results[0].domain
    assert_equal 'ddd.example.com', @context.results[1].domain
  end

  def test_domainのブロックが各ドメインに対して実行されること
    received = []
    @context.domain('aaa.example.com', 'bbb.example.com') do |name|
      received << name
    end

    assert_equal ['aaa.example.com', 'bbb.example.com'], received
  end

  def test_domainに複数ドメインを指定するとブロック内のDSL設定が全ドメインに適用されること
    # DSLメソッドは Dsl::Evaluator のインスタンスメソッドなので instance_eval 経由で呼び出す
    @context.instance_eval do
      domain('aaa.example.com', 'bbb.example.com') do
        no_ssl
      end
    end

    assert_equal true, @context.results[0].no_ssl
    assert_equal true, @context.results[1].no_ssl
  end

  def test_domainに引数なしで例外が発生すること
    assert_raises(RuntimeError) { @context.domain }
  end

  def test_domainにnilのみ指定した場合例外が発生すること
    assert_raises(RuntimeError) { @context.domain(nil) }
  end

  def test_domainにnilを含む引数を指定した場合nilを無視して処理すること
    @context.domain('aaa.example.com', nil, 'bbb.example.com') do
    end

    assert_equal 2, @context.results.length
    assert_equal 'aaa.example.com', @context.results[0].domain
    assert_equal 'bbb.example.com', @context.results[1].domain
  end

  def test_domainに済みのドメインは定義を上書きせず内容を引き継ぐこと
    @context.instance_eval do
      domain('aaa.example.com') { no_ssl }
      domain('aaa.example.com') { adapter 'direct' }
    end

    assert_equal 1, @context.results.length
    assert_equal true, @context.results[0].no_ssl
    assert_equal 'direct', @context.results[0].adapter
  end

  def test_基本的なDSLがConfigContextインスタンスに反映されることの検証
    results = Dsl::Loader.load File.expand_path('test_config_files/test1_basic.conf.rb', __dir__)
    
    # result にドメインが追加されていること
    assert_equal 2, results.length

    config = results[0]
    assert_instance_of ConfigContext, config
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
    assert_instance_of Dsl::Upstream, loc.first
    assert_equal ['webapp1'], loc.first.dest
    assert_nil loc.first.grpc
    
    loc = config.locations['/map_api']
    assert_equal 1, loc.length
    assert_instance_of Dsl::Upstream, loc.first
    assert_equal ['webapp2'], loc.first.dest
    assert_nil loc.first.grpc

    config = results[1]
    assert_instance_of ConfigContext, config
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

  def test_include_fileが相対パスの設定ファイルを読み込めること
    results = Dsl::Loader.load File.expand_path('test_config_files/test_include_file.conf.rb', __dir__)

    assert_equal 2, results.length
    config = results.find { |c| c.domain == 'primary.example.com' }
    included_config = results.find { |c| c.domain == 'included.example.com' }

    assert_equal true, config.no_ssl
    assert_equal 'socat', included_config.adapter
    assert_equal '/mnt/cert.pem', included_config.cert_file
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
    results = Dsl::Loader.load File.expand_path('test_config_files/test2_grpc.conf.rb', __dir__)
    
    assert_equal 1, results.length

    config = results[0]
    assert_instance_of ConfigContext, config
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
    assert_instance_of Dsl::Upstream, loc.first
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

  def test_listen_optionsのDSLがConfigContextインスタンスに反映されることの検証
    results = Dsl::Loader.load File.expand_path('test_config_files/test3_listen_options.conf.rb', __dir__)
    
    assert_equal 2, results.length

    config = results[0]
    assert_instance_of ConfigContext, config
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
    assert_instance_of ConfigContext, config
    assert_equal 'test3-2.example.com', config.domain
    assert_equal 'so_keepalive=on deferred rcvbuf=8192', config.listen_options
  end

  def test_グローバル_nginx_configが複数回の呼び出しで蓄積されること
    results = Dsl::Loader.load File.expand_path('test_config_files/test_global_nginx_config.conf.rb', __dir__)
    
    assert_equal 2, results.length

    # 両方のドメインが同じグローバル設定を持つことを確認
    results.each do |config|
      assert_instance_of ConfigContext, config
      
      # グローバル設定が複数回の呼び出しで蓄積されていることを確認
      global_config = config.get_global_nginx_config
      assert_includes global_config, 'upstream global_backend'
      assert_includes global_config, 'server backend.example.com:3000'
      assert_includes global_config, 'proxy_set_header X-Custom-Global value'
    end

    # 最初のドメイン確認
    config = results[0]
    assert_equal 'domain1.example.com', config.domain
    assert_equal 1, config.locations['/'].length
    assert_equal ['app1'], config.locations['/'].first.dest

    # 2番目のドメイン確認
    config = results[1]
    assert_equal 'domain2.example.com', config.domain
    assert_equal 1, config.locations['/'].length
    assert_equal ['app1'], config.locations['/'].first.dest
  end

end
