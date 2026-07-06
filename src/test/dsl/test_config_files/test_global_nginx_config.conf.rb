# グローバルレベル nginx設定テスト

# グローバル設定を複数回追加
global_nginx_config <<~CONFIG
  upstream global_backend {
    server backend.example.com:3000;
  }
CONFIG

global_nginx_config <<~CONFIG
  proxy_set_header X-Custom-Global value;
CONFIG

# 複数ドメイン
domain('domain1.example.com', 'domain2.example.com') {
  proxy_to 'app1'
}
