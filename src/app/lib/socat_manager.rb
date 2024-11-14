# frozen_string_literal: true
require 'singleton'
require 'lib/functions'

class SocatManager
  include Singleton

  UNIX_SOCKET_BASE_DIR = '/var/spool'

  def initialize
    @dest_list = {}  # { dest => unix_socket } な連想配列
  end

  # socat の使用を登録する
  # @param base_dest [String] 転送先定義（ホスト名:ポート）
  # @return [String] UNIXソケットのファイルパス
  def register(base_dest)
    unix_socket_path, name = _get_unix_socket_path_name base_dest
    unless @dest_list.has_key? base_dest
      @dest_list[base_dest] = name
      _start base_dest, unix_socket_path
    end
    log "SocatManager:: register: #{base_dest} -> #{unix_socket_path}"
    unix_socket_path
  end

  def ensure_process(&proc)
    @dest_list = {}
    proc.call
  ensure
    # @dest_list に含まれていないものは終了させる
    _cleanup @dest_list.keys
  end

  protected
  def _log(str)
    print '%% socat %% '
    puts str
  end

  # socat コマンドライン文字列
  # @param dest             [String] 転送先定義（ホスト名:ポート）
  # @param unix_socket_path [String] UNIXソケットのパス
  # @return [String] socat コマンドライン文字列
  def _get_command(dest, unix_socket_path = nil)
    unix_socket_path ||= _get_unix_socket_path_name(dest).first
    cmd = ['socat']
    cmd << "-lf#{unix_socket_path}.log"
    if ENV['SOCAT_DUMP_LOGS']
      cmd << "-r #{unix_socket_path}.request.dump"
      cmd << "-R #{unix_socket_path}.response.dump"
    end
    cmd << _build_socat_listen(unix_socket_path)
    cmd << "TCP:#{dest}"
    cmd.join ' '
  end

  # socat listen 引数を作る
  def _build_socat_listen(unix_socket_path, *options)
    cmd = ["UNIX-LISTEN:#{unix_socket_path}"]
    cmd << 'fork'
    cmd << 'user=www-data'
    cmd << "backlog=#{self.class.get_so_max_conn}"
    max_children = ENV['SOCAT_MAX_CHILDREN']
    if max_children
      cmd << "max-children=#{max_children}"
    end
    cmd.concat options
    cmd.join ','
  end

  # socat が起動していなかったら起動する
  # @param dest             [String] 転送先定義（ホスト名:ポート）
  # @param unix_socket_path [String] UNIXソケットのファイル名
  # @param if_needed        [Boolean] socat が起動していない場合のみ起動する
  # @return [Integer|nil] 起動した場合は socat プロセスの PID
  def _start(dest, unix_socket_path = nil, if_needed: true)
    cmd = _get_command dest, unix_socket_path
    if if_needed
      pid = _running?(dest, cmd)
      if pid
        _log "already running. PID=#{pid} cmd=#{cmd}"
        return pid
      end
    end
    pid = daemon_exec cmd  # 子プロセスを起動
    _log "started. PID=#{pid} cmd=#{cmd}"
    pid
  end

  # socat が起動しているか判定
  # @param dest             [String] 転送先定義（ホスト名:ポート）
  # @param target_cmd       [String] チェック対象のコマンドライン文字列
  # @return [Integer] 起動している場合はそのプロセスID
  def _running?(dest, target_cmd = nil)
    target_cmd ||= _get_command dest
    # _log "check running?. #{dest} cmd=#{target_cmd}"
    _process_list.each do |pid, cmd|
      return pid if cmd == target_cmd
    end
    nil
  end

  # socat を終了させる
  # @param keep_dests [*String]  終了させない転送先定義（ホスト名:ポート）
  def _cleanup(*keep_dests)
    _log "_cleanup() keep_dests=#{keep_dests}"
    keeps = keep_dests.flatten.compact.map{|x| [_get_command(x), x]}.to_h  # { command => dest } な連想配列
    _process_list.each do |pid, cmd|
      # _log "debug    PID=#{pid} cmd=#{cmd}"
      next if keeps.has_key? cmd  # キープすべきものだったらスキップ
      Process.kill :TERM, pid
      _log "stopped. PID=#{pid} cmd=#{cmd}"
      # UNIXソケットファイルを削除
      mr = cmd.match /UNIX-LISTEN:(.*\.sock)/
      if mr
        File.unlink mr[1] if File.exist? mr[1]
      end
    end
  end

  # socat プロセスを列挙する
  # @return [Enumerator] [pid, cmd] の列挙子
  def _process_list
    Enumerator.new do |y|
      `ps x`.each_line do |x|
        pid,pts,_,time,cmd = x.chomp.split ' ', 5
        next unless cmd.start_with? 'socat'
        # _log "  _process_list yield pid=#{pid}, cmd='#{cmd}'"
        y.yield pid.to_i, cmd
      end
    end
  end

  # 転送先定義名から UNIXソケットファイル名 を求める
  # @param dest_str [String] 転送先定義（ホスト名:ポート）
  def _get_unix_socket_name(dest_str)
    dest_str.gsub /\W/, '_'
  end

  # 転送先定義名から UNIXソケットファイル名 を求める
  # @param dest_str [String] 転送先定義（ホスト名:ポート）
  # @return [Array] [UNIXソケットのファイルパス, UNIXソケットのファイル名]
  def _get_unix_socket_path_name(dest_str)
    n = _get_unix_socket_name dest_str
    ["#{UNIX_SOCKET_BASE_DIR}/#{n}.sock", n]
  end
    
  # somaxconn を読み取る
  def self.get_so_max_conn
    @@max_conn ||= File.read('/proc/sys/net/core/somaxconn').strip
  end
end
