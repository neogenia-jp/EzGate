# EzGate

EzGate は HTTPS に対応したリバースプロキシをお手軽に立てることができる事を目指した Docker コンテナです。

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

```
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

```yml
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

```
domain('www.example.com') {
  proxy_to "webapp1", "webapp2", ...
}
```

複数の `domain()` を記述することが可能です。

さらに、以下のように `cert_email` `nginx_config` のオプション指定が可能です。

```
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

```
domain('localhost') {
  proxy_to 'webapp1:3000'

  cert_file '/mnt/cert.pem'
  key_file '/mnt/key.pem'
}
```

このリポジトリの `example2/` ディレクトリを参照してください。

