# EzGate

EzGate は HTTPS に対応したリバースプロキシをお手軽に立てることができる事を目指した Docker コンテナです。
- WebSocket や gRPC の中継にも対応しています。
- HTTPS を使用せず Plain HTTP で接続を受け付けることも可能です。
- 中継先に接続できない状態でもnginxを起動できます（開発環境向けオプション）。
- 中継したデータを簡単にダンプ出力することができます（デバッグ用）。

[docker hub](https://hub.docker.com/repository/docker/neogenia/ez-gate/general)
[Qiitaでの解説記事](https://qiita.com/lobin-z0x50/items/2d91050fa2e7bffa692a)

## クイックスタート

### 例1

Webアプリが既にあり、それが 192.168.1.101:3000 で稼働していて、ドメインを www1.example.com に割り当てたいとすると、それに対するリバースプロキシを以下のようにして起動することができます。

```bash
docker run -ti -p80:80 -p443:443 -e PROXY_TO=www1.example.com,192.168.1.101:3000 -e CERT_EMAIL=your@email.com neogenia/ez-gate:latest
```

ここで、`CERT_EMAIL` に指定するのは Let'sEncrypt に登録する HTTPS証明書のメールアドレスです。

### 例2

複数のWebアプリに対して複数のドメインを割り当てることもできます。

例えば、Webアプリ1 が ホスト`nginx1` で稼働していて、更に Webアプリ2 が ホスト`apache1` `apache2` で負荷分散として複数稼働している場合、
以下のような設定ファイルを書くことでより詳細にカスタマイズできます。

```ruby:config
domain('www1.example.com') {
  proxy_to 'nginx1'
}

domain('www2.example.com') {
  proxy_to "apache1", "apache2"
}
```

そしてこの設定ファイルを mnt/config として保存し、コンテナにマウントしたら、そのパスを環境変数 `CONFIG_PATH` で指定します。
`docker compose` を使用する場合は以下のような `yml` になります。
（実際にこのリポジトリの `example/` ディレクトリにこの構成が入っています）

```yml:docker-compose.yml
version: '2'

services:
  nginx1:
    container_name: nginx1
    image: nginxdemos/hello

  apache1:
    container_name: apache1
    image: httpd:2.4

  apache2:
    container_name: apache2
    image: httpd:2.4

  gate:
    container_name: gate
    image: neogenia/ez-gate
    build:
      context: ../docker/
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./mnt:/mnt/
    environment:
      CONFIG_PATH: /mnt/config
      CERT_EMAIL: your@email.com
      DEBUG: 1
    depends_on:
      - nginx1
      - apache1
      - apache2
```

## 設定ファイルの書き方

基本構文は以下です。

```ruby:config
domain('www.example.com') {
  proxy_to "webapp1", "webapp2", ...
}
```

複数の `domain()` を記述することが可能です。

さらに、以下のように `cert_email` `nginx_config` のオプション指定が可能です。

```ruby:config
domain('www2.example.com') {
  proxy_to "apache1", "apache2"
  cert_email 'your@email.com'

  nginx_config <<~_CONFIG_
    # change upload size max
    client_max_body_size 100M;
  _CONFIG_
}
```

この設定ファイルは Ruby プログラムとして解釈されますので、変数やメソッドの定義も可能です。
`domain` `cert_email` `nginx_config` 等は実は全て予め定義済みのメソッドです。

なお、`cert_email` は環境変数 `CERT_EMAIL` の指定があればそちらが優先されます。

## 設定ファイルのリロード

設定ファイルを変更した場合、以下のようにリロードコマンドを実行することで
リバースプロキシを停止することなく設定ファイルの内容を反映させることが出来ます。

```bash
docker exec -ti ez-gate /var/scripts/reload_config.rb
```

## 証明書の手動更新

EzGate では12時間ごとに自動的にHTTPS証明書の更新が行われます。
これを手動で実行するには、以下のようにします。

```bash
docker exec -ti ez-gate certbot renew --deploy-hook '/usr/sbin/service nginx reload'
```

## 個別の証明書ファイルを指定する（デバッグ時など）

EzGate は自動的に Let's Encrypt を使ってHTTPS証明書ファイルを作成しますが、
予め用意された証明書ファイルを使って稼働させることも出来ます。

特にローカルで開発環境を構築する場合は、Let's Encrypt の証明書が自動作成できませんので、
`mkcert` などで用意した証明書を指定することでエラーを回避できます。

```bash
# 証明書格納用フォルダを作成
mkdir certs

# mkcertを使って localhost 向けの証明書ファイルを生成
mkcert -install  # 初回のみ
mkcert -key-file certs/key.pem -cert-file certs/cert.pem localhost

# 証明書格納用フォルダをボリュームマウントし、環境変数でそれらのファイルを指定
docker run -ti -p80:80 -p443:443 -e PROXY_TO=localhost,webapp1:3000 -e CERT_FILE=/mnt/cert.pem -e KEY_FILE=/mnt/key.pem -v `pwd`/certs:/mnt neogenia/ez-gate:latest
```

設定ファイルで指定する場合は以下のようになります。

```ruby:config
domain('localhost') {
  proxy_to 'webapp1:3000'

  cert_file '/mnt/cert.pem'
  key_file '/mnt/key.pem'
}
```

このリポジトリの `example2/` ディレクトリを参照してください。

## HTTPSを使用しない

HTTPS を使用せず、Plain HTTP で接続を受け付けるには、`no_ssl` オプションが使用できます。

```ruby:config
domain('localhost') {
  no_ssl  # HTTPSを使用しない
  proxy_to 'webapp1:3000'
}
```

## さらに高度な設定

### アクセス元IPアドレスによって中継先を切り替える

複数サーバでの負荷分散のためにリバースプロキシを使用する場合、ある特定のサーバだけを切り離して検証したい場合があります。
そういった利用シーンを想定し、EzGateではある特定のPCからアクセスした場合のみ、切り離したサーバに中継させることが出来ます。

例えば、アプリケーションサーバを２台で負荷分散する場合、以下のように `proxy_to` にカンマ区切りで中継先を指定します。

```ruby:config
domain('myservice.example.com') {
  # アプリケーションサーバ2台で負荷分散
  proxy_to 'apserver1', 'apserver2'

  cert_file '/mnt/cert.pem'
  key_file '/mnt/key.pem'
}
```

ここで、`apserver1` をメンテナンスのために切り離し、自社のネットワークのグローバルIPからアクセスした時だけ
`apserver1` につながるようにしたい場合は、以下のように `proxy_to` のオプション引数 `from:` を指定します。

```ruby:config
domain('myservice.example.com') {
  # アクセス元IPアドレスが '11.22.33.44' の時だけ、`apserver1` へ中継
  proxy_to 'apserver1', from: '11.22.33.44'
  # それ以外は `apserver2` へ中継
  proxy_to 'apserver2', from: :all   # `from: :all` は省略可能
}
```

このリポジトリの `example3/` ディレクトリにサンプルが入っています。

### 別のドメインへのリダイレクト

ある特定のドメインでアクセスされた時に、別のドメインにリダイレクトさせることも簡単にできます。
よくあるのは、ドメインの移行や、www 無しのドメインでアクセスされた時に www 有りのドメインにリダイレクトさせる、
といった使い方です。

例えば、`example.com` でアクセスされた際に `www.example.com` にリダイレクトさせるための設定は以下のようになります。

```ruby:config
DOMAIN = 'www.example.com'

# `www.` 付きのドメインでアクセスされた時
domain(DOMAIN) {
  proxy_to 'webapp1'   # `webapp1` に中継する

  cert_file '/mnt/cert.pem'
  key_file '/mnt/key.pem'
}

# `www.` 無しのドメインでアクセスされた時
domain(DOMAIN.gsub /^www\./, '') {
  cert_file '/mnt/cert.pem'
  key_file '/mnt/key.pem'

  # `www.` 付きのドメインにリダイレクトする
  nginx_config <<~CONFIG
    location / {
      return 301   https://#{DOMAIN}$request_uri;
    }
  CONFIG

  # または、redirect_to 構文を使用できます
  redirect_to DOMAIN
}
```

上記のように、 `domain() { }` 内に `proxy_to` を指定せず、
代わりに `nginx_config` を使ってリダイレクトの設定を行うだけです。

このリポジトリの `example4/` ディレクトリにサンプルが入っています。

### ロケーションごとに中継先を切り替える

ある特定のパスにアクセスされた時だけ、中継先を切り替えることが出来ます。
（バージョン: 20210318 以降）

例えば、 通常のアクセスは `webapp1` サーバに中継し、 `/map_api` にアクセスされた時だけ
`webapp2` サーバに中継する、といった設定が簡単に出来ます。

```ruby:config
SERVER_IP = '192.168.11.22'

domain("#{SERVER_IP}.nip.io") {
  # デフォルトの中継先
  proxy_to 'webapp1'

  # 特定のパスにアクセスされた時だけ、別サーバに中継する
  location('/map_api') {
    proxy_to 'webapp2'
  }

  cert_file '/mnt/cert.pem'
  key_file '/mnt/key.pem'
}
```

`location() { }` で囲って `proxy_to` を指定することにより、特定のパスだけに絞って中継先を上書きすることが出来ます。
また、`location() { }` の中では、`nginx_config` を指定することも出来ます。
`location` で指定可能なロケーションは、 [`nginx` の `location` ディレクティブ](http://nginx.org/en/docs/http/ngx_http_core_module.html#location)
と同じです。

例えば `location('~* \.(gif|jpg|jpeg)$') { }` と書いた場合、`nginx` の設定ファイルには以下のように展開されます。

```nginx.conf:nginx.conf
location ~* \.(gif|jpg|jpeg)$ {
}
```

このリポジトリの `example5/` ディレクトリにサンプルが入っています。

### ログローテーション

nginx のログローテーションをカスタマイズ出来ます。
デフォルトは1日ごとにファイルを切り替え、過去60日分が保存されます。
（バージョン: 20221125 以降）


```ruby:config
SERVER_IP = '192.168.11.22'

domain("#{SERVER_IP}.nip.io") {
  proxy_to :webapp1

  # ログファイルの保存日数を指定
  logrotate 7     # 過去 7日分を保存
  logrotate 90    # 過去90日分を保存
  logrotate false # ログローテーションしない
}
```

ログファイルを永続化するには、コンテナ内の `/var/log/nginx/` に対してホスト側のディレクトリをマウントする方法があります。
タイムゾーンを変更するには、`TZ` 環境変数を指定してください。

```yml:docker-compose.yml
services:
  nginx1:
    container_name: nginx1
    image: nginxdemos/hello

  gate:
    container_name: gate
    image: neogenia/ez-gate:20221115
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./mnt:/mnt/
      - ./logs:/var/log/nginx/   # ホスト側のディレクトリをマウント
    environment:
      TZ: Asia/Tokyo   # ログに記録されるタイムゾーンを指定
      CONFIG_PATH: /mnt/config
      CERT_EMAIL: your@email.com
      DEBUG: 1
```

### WebSocket

```ruby:config
domain("rails.192.168.11.22.nip.io") {
  proxy_to :rails

  # WebSocket
  location('/cable') {
    proxy_to :rails
    upstream_log true   # 中継先の情報をデバッグするためのログをONにする

    nginx_config <<~CONFIG
      # for WebSocket
      proxy_http_version 1.1;
      proxy_set_header Upgrade websocket;
      proxy_set_header Connection Upgrade;
    CONFIG
  }
}
```

### gRPC

gRPC通信を中継することも可能です。バージョン `20230104` 以降が必要です。
EzGate がSSL終端の役割を担います。クライアントからは SSL での接続が必要です。
中継先のサーバでは SSL は不要です。
（バージョン: 20230726 以降）

```ruby:config
domain("grpc.192.168.11.22.nip.io") {
  # gRPC通信を中継
  grpc_to 'grpc_server1:50051', 'grpc_server2:50051'

  nginx_config <<~CONFIG
    ssl_verify_client off;           # [オプション] クライアントのSSL証明書チェックをしない
    error_page 502 = /error502grpc;
  CONFIG

  # バックエンドが unavailable だった場合は gRPC 形式でエラーを返す
  location('= /error502grpc') {
    nginx_config <<~CONFIG
      internal;
      default_type application/grpc;
      add_header grpc-status 14;
      add_header grpc-message "unavailable all upstreams!";
      return 204;
    CONFIG
  }
}
```

## 開発者向けオプション

開発環境などでは、Dockerコンテナの起動順や再起動など、さまざま事情で中継先に接続できない状態が起こりえます。
通常は、EzGate起動時に中継先の接続チェックが行われますが、`adapter` オプションを指定することでチェックを行わないようになります。
（バージョン: 20240306 以降）

```ruby:mnt/config
domain("vm.192.168.56.101.nip.io") {
  proxy_to 'wordpress:80'

  # アダプターを指定すれば中継先への接続チェックを行わない
  adapter :socat
}
```

また、`adapter :socat` を指定していると、環境変数 `SOCAT_DUMP_LOGS` を追加することで中継データをダンプさせることもできます。
（デバッグ用。本番環境での運用は想定していません）

```yml:docker-compose.yml
services:
  wordpress:
    container_name: wordpress
    image: wordpress:5.6.0-apache

  gate:
    container_name: gate
    image: neogenia/ez-gate:20240306
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./mnt:/mnt/
    environment:
      CONFIG_PATH: /mnt/config
      CERT_EMAIL: your@email.com
      SOCAT_DUMP_LOGS: 1   # 中継データをダンプする
```

コンテナ内の `/var/spool/` 配下にダンプファイルが出力されます。
ファイル名は `*.request.dump` `*.response.dump` となります。

```sh
# コンテナ起動
docker-compose up --build -d

# EzGateコンテナに bash でアタッチ
docker exec -ti gate bash

# ダンプファイルを確認
ls -l /var/spool/
root@8432a255db3e:/# ls -l /var/spool/
total 2452
drwxr-xr-x. 3 root     root    4096 Mar  6 12:03 cron
srwxr-xr-x. 1 www-data root       0 Mar  7 10:14 wordpress_80.sock
-rw-r--r--. 1 root     root       0 Mar  7 10:14 wordpress_80.sock.log
-rw-r--r--. 1 root     root    1055 Mar  7 10:15 wordpress_80.sock.request.dump
-rw-r--r--. 1 root     root    1835 Mar  7 10:15 wordpress_80.sock.response.dump
lrwxrwxrwx. 1 root     root       7 Feb 25 11:02 mail -> ../mail
root@8432a255db3e:/#
```