# frozen_string_literal: true

RSpec.describe RailsDevSsl do
  let(:ssl_dir) { File.join(Dir.pwd, 'ssl') }
  let(:custom_name) { 'custom_directory' }
  let(:custom_dir)  { File.join(Dir.pwd, custom_name) }
  let(:config_path) { File.join(ssl_dir, 'server.csr.cnf') }

  def command(args)
    RailsDevSsl::CLI.start(args.to_s.split(' '))
  end

  around(setup_cleanup: true) do |example|
    command(:setup)
    example.run
    `rm -rf #{ssl_dir}` if Dir.exist?(ssl_dir)
    `rm -rf #{custom_dir}` if Dir.exist?(custom_dir)
  end

  before(create_config: true) do
    command('generate_config --non-interactive')
  end

  before(cleanup_before: true) do
    `rm -rf #{ssl_dir}` if Dir.exist?(ssl_dir)
    `rm -rf #{custom_dir}` if Dir.exist?(custom_dir)
  end

  after(cleanup: true) do
    `rm -rf #{ssl_dir}` if Dir.exist?(ssl_dir)
    `rm -rf #{custom_dir}` if Dir.exist?(custom_dir)
  end

  it 'has a version number' do
    expect(RailsDevSsl::VERSION).not_to be nil
  end

  describe 'setup', :cleanup_first do
    it 'creates an ssl directory in the project root' do
      expect(Dir.exist?(ssl_dir)).to be false
      command(:setup)
      expect(Dir.exist?(ssl_dir)).to be true
    end

    it 'creates a user-defined directory' do
      expect(Dir.exist?(custom_dir)).to be false
      command("setup #{custom_dir}")
      expect(Dir.exist?(custom_dir)).to be true
    end
  end

  describe 'generate_config', :setup_cleanup do
    it 'creates a config file' do
      expect(Dir.exist?(ssl_dir)).to be true
      command('generate_config --non-interactive')
      expect(File.exist?(config_path))
      expect(File.readlines(config_path)).to be_include("ST=California\n")
    end

    it 'creates a config file with custom info', :cleanup do
      allow($stdin).to receive(:gets).and_return('CA')
      command(:generate_config)
      expect(File.readlines(config_path)).to be_include("O=CA\n")
    end
  end

  describe 'generate_v3_ext_file', :setup_cleanup do
    it 'creates a v3.ext file', :create_config do
      expect(File.exist?(File.join(ssl_dir, 'v3.ext'))).to be false
      command(:generate_v3_ext_file)
      expect(File.exist?(File.join(ssl_dir, 'v3.ext'))).to be true
    end

    it 'raises an exception if the config is missing' do
      expect(File.exist?(File.join(ssl_dir, 'server.csr.cnf'))).to be false
      expect { command(:generate_v3_ext_file) }.to raise_exception(RuntimeError)
    end

    it 'uses the CN from server.csr.cnf', :create_config do
      command(:generate_v3_ext_file)
      cn = OpenSSL::Config.load(File.join(ssl_dir, 'server.csr.cnf'))['dn']['CN']
      dns = OpenSSL::Config.load(File.join(ssl_dir, 'v3.ext'))['alt_names']['DNS.1']
      expect(cn).to eq(dns)
    end
  end

  describe 'generate_certificates', :setup_cleanup do
    it 'creates a root certificate key file', :create_config do
      expect(Dir.exist?(ssl_dir)).to be true
      command(:generate_certificates)
      expect(File.exist?(File.join(ssl_dir, 'rootCA.key'))).to be true
    end

    it 'creates a v3.ext file for subject alternative name', :create_config do
      command(:generate_certificates)
      expect(File.exist?(File.join(ssl_dir, 'v3.ext'))).to be true
    end

    it 'creates self-signed key and crt files', :create_config do
      command(:generate_certificates)
      expect(File.exist?(File.join(ssl_dir, 'server.crt'))).to be true
      expect(File.exist?(File.join(ssl_dir, 'server.key'))).to be true
      expect(File.exist?(File.join(ssl_dir, 'server.csr'))).to be false
    end
  end

  describe 'display_certificate', :setup_cleanup do
    it 'outputs to stdout', :create_config do
      command(:generate_certificates)
      expect { command(:display_certificate) }.to output(/Certificate:/).to_stdout
    end
  end
end
