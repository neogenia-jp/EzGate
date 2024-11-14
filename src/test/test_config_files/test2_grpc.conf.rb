# grpc
domain("192.168.1.101.nip.io") {

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
