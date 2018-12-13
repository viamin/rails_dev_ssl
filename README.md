# RailsDevSsl

`rails_dev_ssl` is a command line utility that takes some of the work out of generating the SSL certificates for local development.

This utility will help you set up your development machine to serve your Rails API over HTTPS.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'rails_dev_ssl', group: :development
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install rails_dev_ssl

## Usage

#### Generate certificates

`rails_dev_ssl generate_certificates` will create a new directory in your project folder called "ssl" and ask for information to be added to your local certificate authority. Inside the `ssl` directory will be your config file and `server.crt` and `server.key` files.

#### Configuring puma

If you use puma to serve your app, you can use your new certificates by passing them when calling puma:

```
puma -C config/puma.rb -b 'ssl://127.0.0.1:<port>?key=./ssl/server.key&cert=./ssl/server.crt'
```

or in `config/puma.rb`:

```
ssl_bind '127.0.0.1', '<port>', {
  key: ./ssl/server.key,
  cert: ./ssl/server.crt
}
```

#### Customization

You can change the certificate directory using `setup <directory>`, for example, `rails_dev_ssl setup lib/ssl` to put the certificates inside your lib directory.

You can generate the `server.crt.cnf` file using the `generate_config` command.

#### Browser warnings

When you use your first self-signed certificate, your browser will warn you about an untrusted certificate authority. You'll need to trust the rootCA you created for your project.

Chrome and Firefox will ask you to add the certificate authority in the app. To use Safari, you'll need to add the CA to your keychain. You can do this with the `add_ca_to_keychain` command.

#### /etc/hosts

You may want to add an entry to your `/etc/hosts` file to include the CN you set in the `generate_config` step. This will allow you to visit the domain in your browser instead of using 127.0.0.1 (for example, https://localhost.ssl/path/to/your/app.)

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

Note that `rake spec` will remove any existing `ssl` directory in your current working directory.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/viamin/rails_dev_ssl.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
