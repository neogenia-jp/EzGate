domain('test3-1.example.com') {
  proxy_to 'rails'
  listen_options 'so_keepalive=on'
}

rcvbuf = 8192
domain('test3-2.example.com') {
  proxy_to 'rails'
  # 複数指定、シンボル指定まじり
  listen_options 'so_keepalive=on', :deferred, "rcvbuf=#{rcvbuf}"
}
