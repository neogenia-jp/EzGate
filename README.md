# Ez Gate

Ez Gate is a docker container that aims to make it easy to set up a reverse proxy that supports HTTPS.

[日本語版](./README.ja.md)

## Quick start

### exapmle 1:

There's already a web app, and it's running at 192.168.1.101:3000, and If you want to assign the domain to www1.expample.com, you can use the You can start the reverse proxy as follows

```bash
docker run -ti -p80:80 -p443:443 -e PROXY_TO=www1.expample.com,192.168.1.101:3000 -e CERT_EMAIL=your@email.com neogenia/EzGate:latest
```

Here, `CERT_EMAIL` is the email address of the HTTPS certificate you want to register with Let'sEncrypt.

### 例2

You can also assign multiple domains to multiple web apps.

For example, if web app 1 is running on host `nginx1` and web app 2 is running on host `apache1` `apache2` as a load balancer,
 you can customize it in more detail by writing a configuration file like the following:

```
domain('www1.example.com') {
  proxy_to 'nginx1'
}

domain('www2.example.com') {
  proxy_to "apache1", "apache2"
}
```

Then, save the configuration file as `mnt/config` and mount it in the container, and set its path to the environment variable `CONFIG_PATH`.
If you use `docker compose`, the `yml` will look like this: 
 (Actually, you can put it in the `example/` directory of this repository.)

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

## Syntax of configuration file

basic syntax:

```
domain('www.example.com') {
  proxy_to "webapp1", "webapp2", ...
}
```

It is possible to write multiple `domain()` entries.

In addition, you can specify `cert_email` `nginx_config` options as follows.

```
domain('www2.example.com') {
  proxy_to "apache1", "apache2"
  cert_email 'your@email.com'

  nginx_config <<~_CONFIG_
    # change upload size max
    client_max_body_size 100M;
  _CONFIG_
```

Since this configuration file is interpreted as a Ruby program, you can also define variables and methods.
The `domain` `cert_email` `nginx_config` etc. are all predefined methods.

Note that `cert_email` takes precedence over the environment variable `CERT_EMAIL` if it is specified.

