# frozen_string_literal: true
require_relative 'socat_manager'
require_relative 'domain_util'

class Upstream
  attr_reader :name, :dest, :from_ips, :grpc
  attr_accessor :socat

  # @param domain   [String]        ドメイン名
  # @param dest     [Array<String>] 中継先定義（配列で複数指定可能）
  # @param from_ips [String]        接続元IPアドレス（配列で複数指定可能） 'all' なら指定しないのと同じ
  # @param grpc     [Boolean]       gRPCモードにするかどうか
  # @param socat    [Boolean|Hash]  socatでラップするかどうか
  def initialize(domain, dest, from_ips = nil, grpc = nil, socat = nil)
    @@index ||= 0
    @@index += 1
    @name = "#{DomainUtil.normalize_name domain}-#{@@index}"
    @dest = [dest].flatten
    if from_ips && from_ips.to_s != 'all'
      @from_ips = [from_ips].flatten
    end
    @grpc = grpc
    @socat = socat
  end

  def proxy_to; @dest; end

  def check
    _check_array :proxy_to
    if from_ips
      _check_array :from_ips
      from_ips.each { |ip| _check_ip ip }
    end
  end

  # @return [Array<String>] nginxコンフィグの upstream.server に書き出す中継先一覧
  def dest
    return @dest if !@socat
    @dest.map do |d|
      # socat 経由に差し替え。デコレータパターン??
      file_path = SocatManager.instance.register d
      "unix:#{file_path}"
    end
  end

  private

  REGEXP_IP_ADDR = %r`^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)?$`
  def _check_ip(ip)
    mr = REGEXP_IP_ADDR.match ip 
    raise "invalid ip address '#{ip}'" unless mr
  end

  def _check_array(var_name)
    val = send var_name
    if !val.is_a?(Array) || val.length == 0
      raise "Array '#{var_name}' must has any elements!" 
    end
  end
end

