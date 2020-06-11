# Ez Gate

Ez Gate は HTTPS に対応したリバースプロキシをお手軽に立てることができる事を目指した Docker コンテナです。

## クイックスタート

### 例1

Webアプリが既にあり、それが 192.168.1.101:3000 で稼働していて、ドメインを www1.expample.com に割り当てたいとすると、それに対するリバースプロキシを以下のようにして起動することができます。

```bash
docker run -ti -p80:80 -p443:443 -e PROXY_TO=www1.expample.com,192.168.1.101:3000 -e CERT_EMAIL=your@email.com neogenia/EzGate:latest
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
    image: neogenia/EzGate
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

