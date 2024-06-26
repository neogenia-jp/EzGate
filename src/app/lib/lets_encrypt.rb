# frozen_string_literal: true

class LetsEncrypt
  SETUP_LETSENCRIPT_SCRIPT = '/var/scripts/app/setup_letsencrypt.sh'

  def self.setup(config)
    shell_exec "APP_DOMAIN=#{config.domain}", "LETS_ENCRYPT_CERT_MAIL=#{config.cert_email}", 'bash', SETUP_LETSENCRIPT_SCRIPT
  end
end

