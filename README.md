# EzGate

EzGate is a Docker container that aims to provide an easy reverse proxy for HTTPS.
- It also supports WebSocket and gRPC relay.
- It is also possible to accept connections via Plain HTTP without using HTTPS.
- nginx can be started even when the connection to the relay destination is not available (option for development environment).
- Relayed data can be easily dumped out (for debugging).

[docker hub](https://hub.docker.com/repository/docker/neogenia/ez-gate/general)

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

## Manual certificate renewal

EzGate automatically renews the HTTPS certificate every 12 hours.
To do this manually, do the following:

```bash
docker exec -ti ez-gate certbot renew --deploy-hook '/usr/sbin/service nginx reload'
````

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

## Do not use HTTPS

To accept connections over Plain HTTP instead of using HTTPS, the `no_ssl` option can be used.

```ruby:config
domain('localhost') {
  no_ssl  # HTTPSを使用しない
  proxy_to 'webapp1:3000'
}
```

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

  # or you can use the 'redirect_to' syntax
  redirect_to DOMAIN
}
```

As shown above, we do not specify `proxy_to` in `domain() { }`,
instead we just use `nginx_config` to configure the redirection.

You can find the example in the `example4/` directory of this repository.

### Switching the relay destination for each location

It is possible to switch the forwarding destination only when a specific path is accessed.
(Version: 20210318 or later)

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

### Log rotation

You can customize nginx log rotation.
The default is to switch files every day and keep the last 60 days.
(Version: 20221125 or later)

```ruby:config
SERVER_IP = '192.168.11.22'

domain("#{SERVER_IP}.nip.io") {
  proxy_to :webapp1

  # Specify the number of days to keep the log file
  logrotate 7     # keep last 7 days.
  logrotate 90    # keep last 90 days.
  logrotate false # never rotation.
}
```

To make log files persistent, you can mount the host directory against `/var/log/nginx/` in the container.
To change the time zone, specify the `TZ` environment variable.

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
      - ./logs:/var/log/nginx/   # Mount host-side directory
    environment:
      TZ: Asia/Tokyo   # Specify time zone to be logged
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
    upstream_log true   # enable logging for debug to upstream info

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

It is also possible to relay gRPC communications. Version `20230104` or later is required.
EzGate takes the role of SSL termination. The client needs to connect using SSL.
SSL is not required on the upstream server.
(Version: 20230726 or later)

```ruby:config
domain("grpc.192.168.11.22.nip.io") {
  # proxy gRPC connection.
  grpc_to 'grpc_server1:50051', 'grpc_server2:50051'

  nginx_config <<~CONFIG
    ssl_verify_client off;           # [Optional] Do not check client SSL certificates
    error_page 502 = /error502grpc;
  CONFIG

  # Return error in gRPC format if backend is unavailable
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
## Using open-appsec
EzGate can provide WAF functionality by integrating with the open-appsec agent.


### Configuration
Below is an example of a docker-compose.yml file that runs the open-appsec agent on the same Docker network as the EzGate container.

```docker-compose.yml
services:
  appsec-agent:
    image: ghcr.io/openappsec/agent:${APPSEC_VERSION}
    container_name: appsec-agent
    environment:
      - SHARED_STORAGE_HOST=appsec-shared-storage
      - LEARNING_HOST=appsec-smartsync
      - TUNING_HOST=appsec-tuning-svc
      - https_proxy=${APPSEC_HTTPS_PROXY}
      - user_email=${APPSEC_USER_EMAIL}
      - AGENT_TOKEN=${APPSEC_AGENT_TOKEN}
      - autoPolicyLoad=${APPSEC_AUTO_POLICY_LOAD}
      - registered_server="NGINX"
    ipc: shareable
    restart: unless-stopped
    volumes:
      - ${APPSEC_CONFIG}:/etc/cp/conf
      - ${APPSEC_DATA}:/etc/cp/data
      - ${APPSEC_LOGS}:/var/log/nano_agent
      - ${APPSEC_LOCALCONFIG}:/ext/appsec
      - shm-volume:/dev/shm/check-point
    command: /cp-nano-agent

  gate:
    container_name: gate
    image: neogenia/ez-gate:latest
    ipc: service:appsec-agent
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./mnt:/mnt/
      - shm-volume:/dev/shm/check-point
    environment:
      DEBUG: 1
      TZ: Asia/Tokyo
      CERT_EMAIL: your@email.com
      CONFIG_PATH: /mnt/config

volumes:
  shm-volume:
    driver: local
```
Please configure the environment variables as follows.

The token string to set in `APPSEC_AGENT_TOKEN` should be obtained in advance from the open-appsec management console.

```shell
# open-appsec
export APPSEC_AGENT_TOKEN=your-authentication-token
export APPSEC_ROOT_DIR=./openappsec
export APPSEC_VERSION=latest
export APPSEC_CONFIG=${APPSEC_ROOT_DIR}/appsec-config
export APPSEC_DATA=${APPSEC_ROOT_DIR}/appsec-data
export APPSEC_LOGS=${APPSEC_ROOT_DIR}/appsec-logs
export APPSEC_LOCALCONFIG=${APPSEC_ROOT_DIR}/appsec-localconfig
export APPSEC_AUTO_POLICY_LOAD=false
export APPSEC_HTTPS_PROXY=
export APPSEC_USER_EMAIL=
```

## Developer Options

In a development environment, it is possible for various reasons,
such as the order in which Docker containers are started, restarts, etc., to prevent connections to relay destinations.
Normally, a connection check of the relay destination is performed when EzGate is started,
but by specifying the `adapter` option, the check is not performed.
(Version: 20240306 or later)

```ruby:mnt/config
domain("vm.192.168.56.101.nip.io") {
  proxy_to 'wordpress:80'

  # If an adapter is specified, connection checks to relay destinations are not performed.
  adapter :socat
}
```

Also, if `adapter :socat` is specified, relay data can be dumped by adding the environment variable `SOCAT_DUMP_LOGS`.
(For debugging. It is not intended for operation in a production environment.)

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
      SOCAT_DUMP_LOGS: 1   # Dumping relay data
```

A dump files will be output under `/var/spool/` in the container.
The file name will be `*.request.dump` `*.response.dump`.

```sh
# Start container
docker-compose up --build -d

# Attach to EzGate container with bash
docker exec -ti gate bash

# Check dump files
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
