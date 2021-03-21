# EzGate

EzGate is a docker container that aims to make it easy to set up a reverse proxy that supports HTTPS.

[日本語版](./README.ja.md)

## Quick start

### exapmle 1:

There's already a web app, and it's running at 192.168.1.101:3000, and If you want to assign the domain to www1.example.com, you can use the You can start the reverse proxy as follows:

```bash
docker run -ti -p80:80 -p443:443 -e PROXY_TO=www1.example.com,192.168.1.101:3000 -e CERT_EMAIL=your@email.com neogenia/ez-gate:latest
```

Here, `CERT_EMAIL` is the email address of the HTTPS certificate you want to register with Let'sEncrypt.

### example 2:

You can also assign multiple domains to multiple web apps.

For example, if web app 1 is running on host `nginx1` and web app 2 is running on host `apache1` `apache2` as a load balancer,
 you can customize it in more detail by writing a configuration file like the following:

```ruby:config
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

```yml:docker-compose:yml
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

## Syntax of configuration file

basic syntax:

```ruby:config
domain('www.example.com') {
  proxy_to "webapp1", "webapp2", ...
}
```

It is possible to write multiple `domain()` entries.

In addition, you can specify `cert_email` `nginx_config` options as follows:

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
docker run -ti -p80:80 -p443:443 -e PROXY_TO= localhost,webapp1:3000 -e CERT_FILE=/mnt/cert.pem -e KEY_FILE=/mnt/key.pem -v `pwd`/certs:/ mnt neogenia/ez-gate:latest
```

If you specify it in the configuration file, it looks like the following:

```ruby:config
domain('localhost') {
  proxy_to 'webapp1:3000'

  cert_file '/mnt/cert.pem'
  key_file '/mnt/key.pem'
}
```

See the `example2/` directory in this repository.

## More advanced settings

### Switch the relay destination according to the access source IP address

When using a reverse proxy for load balancing on multiple servers, there are times when you want to isolate a specific server for verification.
In this case, EzGate can relay only the access from a specific PC to the isolated server.

For example, to load-balance two application servers, specify the relay destination in `proxy_to` separated by commas as follows.

```ruby:config
domain('myservice.example.com') {
  # Load balancing with two application servers
  proxy_to 'apserver1', 'apserver2'

  cert_file '/mnt/cert.pem'
  key_file '/mnt/key.pem'
}
```

Now, if you want to detach `apserver1` for maintenance and connect to `apserver1` only when you access it from the global IP of your own network,
specify the optional argument `from:` for `proxy_to` as follows.

```ruby:config
domain('myservice.example.com') {
  # Relay to `apserver1` only when the access source IP address is '11.22.33.44'.
  proxy_to 'apserver1', from: '11.22.33.44'
  # Otherwise, relay to `apserver2`.
  proxy_to 'apserver2', from: :all    # `from: :all` can be omitted.
}
```

You can find the sample in the `example3/` directory of this repository.

### Redirecting to another domain

It is also easy to redirect visitors to a different domain when they access the site from a particular domain.
Common uses are domain migration, or redirecting to a domain with www when accessed from a domain without www.

For example, to redirect to www.example.com when accessed from example.com,
 the configuration is as follows

```ruby:config
DOMAIN = 'www.example.com'

# with `www.` domain
domain(DOMAIN) {
  proxy_to 'webapp1'

  cert_file '/mnt/cert.pem'
  key_file '/mnt/key.pem'
}

# without `www.` domain
domain(DOMAIN.gsub /^www\./, '') {
  cert_file '/mnt/cert.pem'
  key_file '/mnt/key.pem'

  # redirect to `www.` domain
  nginx_config <<~CONFIG
    location / {
      return 301   https://#{DOMAIN}$request_uri;
    }
  CONFIG
}
```

As shown above, we do not specify `proxy_to` in `domain() { }`,
instead we just use `nginx_config` to configure the redirection.

You can find the example in the `example4/` directory of this repository.

### Switching the relay destination for each location

It is possible to switch the forwarding destination only when a specific path is accessed.

For example, you can easily configure the `webapp1` server to relay normal accesses,
and the `webapp2` server to relay only when `/map_api` is accessed.

```ruby:config
SERVER_IP = '192.168.11.22'

domain("#{SERVER_IP}.nip.io") {
  # default server.
  proxy_to 'webapp1'

  # send to a different server for a specific location.
  location('/map_api') {
    proxy_to 'webapp2'
  }

  cert_file '/mnt/cert.pem'
  key_file '/mnt/key.pem'
}
```

By enclosing `location() { }` and specifying `proxy_to`,
you can override the relay destination by focusing on a specific path.
You can also specify `nginx_config` in `location() { }`.
The locations that can be specified with `location` are the same as in the [`nginx`'s `location` directive](http://nginx.org/en/docs/http/ngx_http_core_module.html#location).

For example, if you write `location('~* \. (gif|jpg|jpeg)$') { }`, the following will be expanded in the `nginx` configuration file.

```nginx.conf:nginx.conf
location ~* \.(gif|jpg|jpeg)$ {
}
```

You can find the example in the `example5/` directory of this repository.
