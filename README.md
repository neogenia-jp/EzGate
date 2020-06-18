# Ez Gate

Ez Gate is a docker container that aims to make it easy to set up a reverse proxy that supports HTTPS.

[日本語版](./README.ja.md)

## Quick start

### exapmle 1:

There's already a web app, and it's running at 192.168.1.101:3000, and If you want to assign the domain to www1.expample.com, you can use the You can start the reverse proxy as follows:

```bash
docker run -ti -p80:80 -p443:443 -e PROXY_TO=www1.expample.com,192.168.1.101:3000 -e CERT_EMAIL=your@email.com neogenia/EzGate:latest
```

Here, `CERT_EMAIL` is the email address of the HTTPS certificate you want to register with Let'sEncrypt.

### example 2:

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

In addition, you can specify `cert_email` `nginx_config` options as follows:

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

Since this configuration file is interpreted as a Ruby program, you can also define variables and methods.
The `domain` `cert_email` `nginx_config` etc. are all predefined methods.

Note that `cert_email` takes precedence over the environment variable `CERT_EMAIL` if it is specified.

## Reload the configuration file.

If you change the configuration file, you can run the reload command as follows
to change the You can reflect the contents of the configuration file without stopping the reverse proxy.

```bash
docker exec -ti ez-gate /var/scripts/reload_ config.rb
```

## Specify a separate certificate file (e.g. for debugging)

EzGate automatically uses Let's Encrypt to create an HTTPS certificate file,
but you can also run it using a pre-made certificate file.

If you build a local development environment,
you can avoid the error by specifying a certificate prepared by `mkcert` and so on,
because Let's Encrypt certificate cannot be created automatically.

```bash
# Create a folder for storing certificates
mkdir certs

# to Generate a certificate file for the localhost using mkcert
mkcert -install # First time only
mkcert -key-file certs/key.pem -cert-file certs /cert.pem localhost

# Volume mount the folder for storing certificates and specify those files in an environment variables
docker run -ti -p80:80 -p443:443 -e PROXY_TO= localhost,webapp1:3000 -e CERT_FILE=/mnt/cert .pem -e KEY_FILE=/mnt/key.pem -v `pwd`/certs:/ mnt neogenia/ez-gate:latest
```

If you specify it in the configuration file, it looks like the following:

```
domain('localhost') {
  proxy_to 'webapp1:3000'

  cert_file '/mnt/cert.pem'
  key_file '/mnt/key.pem'
}
```

See the `example2/` directory in this repository.
