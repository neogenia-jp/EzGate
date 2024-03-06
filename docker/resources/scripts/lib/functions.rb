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

# 子プロセスを起動する
# @param [Array<String>] cmd
# @param [Boolean] detach 子プロセスを切り離して、親が終了しても ゾンビ状態にならないようにする
def shell_spawn(*cmd, detach: true)
  cmd_line = cmd.join(' ')
  log('SHELL_SPAWN:', cmd_line)
  pid = spawn cmd_line
  if detach
    Process.detach pid
  end
  pid
end
