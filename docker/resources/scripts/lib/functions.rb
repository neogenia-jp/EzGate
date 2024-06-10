# frozen_string_literal: true

def log(*messages, **h)
  a = []
  messages.each do |msg|
    a << msg
  end
  h.each do |k, v|
    next unless v
    a << "#{k}=#{v}"
  end
  puts a.join(' ')
end

# シェルでコマンドを実行する
# @param [Array<String>] cmd
# @return [Integer] exit_status
def shell_exec(*cmd)
  cmd_line = cmd.join(' ')
  log('SHELL_EXEC:', cmd_line)
  `#{cmd_line}`
  exit_status = $?.exitstatus
  if exit_status != 0
    raise "## ERROR ## exit status: #{exit_status} command_line: '#{cmd_line}'"
  end
  exit_status
end

# デーモンプロセスを起動する
# @param [Array<String>] cmd
# @return [Integer] プロセスID
def daemon_exec(*cmd)
  cmd_line = cmd.join(' ')
  pid = Process.fork do
    Process.daemon
    Process.exec(cmd_line)
  end
  Process.detach pid
  log('DAEMON_EXEC:', cmd_line)
  pid
end
