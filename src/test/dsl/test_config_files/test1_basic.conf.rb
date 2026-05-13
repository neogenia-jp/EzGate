# 基本パターン
domain('test1.example.com') {
  proxy_to 'webapp1'
  adapter :socat

  # send to a different server for a specific location.
  location('/map_api') {
    proxy_to 'webapp2'
    no_ssl             # locaion スコープに関係なく domain 全体で有効になる
    upstream_log true  # locaion スコープに関係なく domain 全体で有効になる
  }

  cert_email 'w.maeda@neogenia.co.jp'
  cert_file '/mnt/cert.pem'
  key_file '/mnt/key.pem'

  logrotate 5, :weekly
}

# nginx_config 連結テスト
domain("test2.example.com") {
  proxy_to 'webapp3', 'webapp4:8082'

  nginx_config <<~CONFIG
    proxy_http_version 1.1;
  CONFIG

  logrotate 7

  nginx_config <<~CONFIG
    location / {
      return 301   https://test3.example.com$request_uri;
    }
  CONFIG

  redirect_to 'test4.example.com'
}

