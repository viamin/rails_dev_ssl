# frozen_string_literal: true

require 'rails_dev_ssl/version'
require 'thor'
require 'securerandom'
require 'shellwords'
require 'tempfile'
require 'rubygems/user_interaction'
require 'openssl'
# require "pry"

module RailsDevSsl
  class CLI < Thor
    @@dir = ''
    @@config = {}

    desc 'setup [directory]', "creates a new ssl directory (defaults to #{File.join(Dir.pwd, 'ssl')}"
    def setup(dir = File.join(Dir.pwd, 'ssl'))
      @@dir = dir
      Dir.mkdir(@@dir) unless Dir.exist?(@@dir)
    end

    desc 'display_certificate', 'displays the information in your SSL certificate'
    def display_certificate
      raise 'Certificate missing. Have you generated the certificate already?' unless File.exist?(File.join(dir, 'server.crt'))

      puts `openssl x509 -text -in #{File.join(dir, 'server.crt')} -noout`
    end

    desc 'generate_certificates', 'generate SSL certificates'
    option :'pem-file', type: :boolean, default: false
    def generate_certificates
      raise "Directory (#{dir}) doesn't exist" unless Dir.exist?(dir)

      generate_config unless File.exist?(File.join(dir, 'server.csr.cnf'))
      begin
        temp_file = password_file
        safe_path = Shellwords.escape(temp_file.path)
        generate_ca(safe_path)
        generate_crt_and_key(options['pem-file'], safe_path)
      ensure
        temp_file.close!
      end
    end

    desc 'add_ca_to_keychain', 'add certificate to OS X keychain (requires admin privileges)'
    def add_ca_to_keychain
      puts 'Adding rootCA.pem to system keychain'
      `sudo -p 'sudo password:' security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain #{File.join(dir, 'rootCA.pem')}`
    end

    # desc 'add_hosts_entry', 'add an entry to /etc/hosts to include the domain set in your certificate'
    # def add_hosts_entry(hosts_file = '/etc/hosts')
    #   entries = File.readlines(hosts_file).delete_if { |line| line.start_with?('#') }.map { |line| line.split(/\s/) }
    #   if entries.include?(['127.0.0.1', config['CN']])
    #     puts "/etc/hosts already contains an entry for #{config['CN']}"
    #     return
    #   end
    #   new_entry = "127.0.0.1\t#{config['CN']}\n"
    #   `sudo -p 'sudo password:' sh -c "echo #{new_entry} >> /etc/hosts"`
    # end

    desc 'generate_config', 'configure certificate information'
    option :'non-interactive', type: :boolean, default: false
    def generate_config
      unless options['non-interactive']
        country = ask("Enter the country of your organization [#{default_config[:C]}]")
        state = ask("Enter the state of province of your organization [#{default_config[:ST]}]")
        city = ask("Enter the city of your organization [#{default_config[:L]}]")
        org = ask("Enter your organization name [#{default_config[:O]}]")
        email = ask("Enter your email [#{default_config[:emailAddress]}]")
        domain = ask("Enter your local SSL domain [#{default_config[:CN]}]")
        @@config = { C: country, ST: state, L: city, O: org, emailAddress: email, CN: domain }
      end
      write_config_file
    end

    desc 'generate_v3_ext_file', 'generate subject alternative name extension file'
    def generate_v3_ext_file
      raise 'server.csr.cnf missing. run rails_dev_ssl generate_config first' unless File.exist?(File.join(dir, 'server.csr.cnf'))

      puts "\n*** generating v3.ext"
      configs = <<~CONFIG
        authorityKeyIdentifier=keyid,issuer
        basicConstraints=CA:FALSE
        keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
        subjectAltName = @alt_names

        [alt_names]
        DNS.1 = #{config['CN']}
      CONFIG
      File.open(File.join(dir, 'v3.ext'), 'w') { |file| file.write(configs) }
    end

    private

    def ask(question)
      puts question
      $stdin.gets.chomp
    end

    def config
      @config ||= if File.exist?(File.join(dir, 'server.csr.cnf'))
                    OpenSSL::Config.load(File.join(dir, 'server.csr.cnf'))['dn']
                  else
                    default_config.merge(@@config.delete_if { |_k, v| v == '' })
      end
    end

    def default_config
      {
        C: 'US',
        ST: 'California',
        L: 'San Francisco',
        O: 'My Organization',
        emailAddress: 'rails-dev-ssl-user@example.com',
        CN: 'localhost.ssl'
      }
    end

    def dir
      # TODO: read this from an environment variable
      setup if @@dir == ''
      @@dir
    end

    def generate_ca(password_file_path)
      puts "\n*** generating rootCA.key"
      `openssl genrsa -des3 -out #{File.join(dir, 'rootCA.key')} -passout file:#{password_file_path} 2048` unless File.exist?(File.join(dir, 'rootCA.key'))

      puts "\n*** generating rootCA.pem"
      `openssl req -x509 -new -nodes -key #{File.join(dir, 'rootCA.key')} -sha256 -days 1024 -out #{File.join(dir, 'rootCA.pem')} -passin file:#{password_file_path} -config #{File.join(dir, 'server.csr.cnf')}` unless File.exist?(File.join(dir, 'rootCA.pem'))
    end

    def generate_crt_and_key(_pem_file = false, password_file_path)
      puts "\n*** generating server.key"
      `openssl req -new -sha256 -nodes -out #{File.join(dir, 'server.csr')} -newkey rsa:2048 -keyout #{File.join(dir, 'server.key')} -config #{File.join(dir, 'server.csr.cnf')} -passin file:#{password_file_path}`

      generate_v3_ext_file unless File.exist?(File.join(dir, 'v3.ext'))

      puts "\n*** generating server.crt"
      `openssl x509 -req -in #{File.join(dir, 'server.csr')} -CA #{File.join(dir, 'rootCA.pem')} -CAkey #{File.join(dir, 'rootCA.key')} -CAcreateserial -out #{File.join(dir, 'server.crt')} -days 500 -sha256 -extfile #{File.join(dir, 'v3.ext')} -passin file:#{password_file_path}`
      # remove intermediary file
      File.delete(File.join(dir, 'server.csr'))
    end

    def password_file(password = temp_password)
      file = Tempfile.new('some_file')
      file.write(password)
      file.close
      file
    end

    def temp_password
      # We don't really care what the password is since this is only used on localhost
      @temp_password ||= SecureRandom.hex(64)
    end

    def write_config_file
      puts "\n*** Writing server.csr.cnf"
      config_options = <<~CONFIG
        [req]
        default_bits = 2048
        prompt = no
        default_md = sha256
        distinguished_name = dn

        [dn]
        C=#{config[:C]}
        ST=#{config[:ST]}
        L=#{config[:L]}
        O=#{config[:O]}
        OU=Test Domain
        emailAddress=#{config[:emailAddress]}
        CN=#{config[:CN]}
      CONFIG
      File.open(File.join(dir, 'server.csr.cnf'), 'w') { |file| file.write(config_options) }
    end
  end

  class Error < StandardError; end
end
