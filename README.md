[![Gem Version](https://badge.fury.io/rb/altcha-rails.svg)](https://badge.fury.io/rb/altcha-rails)

# Ruby gem for ALTCHA

[ALTCHA](https://altcha.org/) is a protocol designed for safeguarding against spam and abuse by utilizing a proof-of-work mechanism. This protocol comprises both a client-facing widget and a server-side verification process.

`altcha-ruby` is a Ruby gem that provides a simple way to integrate ALTCHA into your Ruby on Rails application.

The main functionality of the gem is to generate a challenge and verify the response from the client. This is done in the library code. An initializer and a controller is installed in the host application to handle the challenge generation and verification.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'altcha-rails'
```

Then execute `bundle install` to install the gem for your application.

Next, run the generator to install the initializer and the controller:

```
$ rails generate altcha:install
      create  app/models/altcha_solution.rb
      create  app/controllers/altcha_controller.rb
      create  config/initializers/altcha.rb
       route  get '/altcha', to: 'altcha#new'
      create  db/migrate/20240211145410_create_altcha_solutions.rb
```

This will create an initializer file at `config/initializers/altcha.rb` and a controller at `app/controllers/altcha_controller.rb` as well as a route in `config/routes.rb` and a model at `app/models/altcha-solutions.rb` (see below).

You will also have to run 'rails db:migrate` to apply pending changes to the database.

## Configuration

The initializer file `config/initializers/altcha.rb` contains the following configuration options:

```ruby
Altcha.setup do |config|
  config.algorithm = 'SHA-256'
  config.num_range = (50_000..500_000)
  config.timeout = 5.minutes
  config.hmac_key = 'change-me'
end
```

The `algorithm` option specifies the hashing algorithm to use and must currently be set to `SHA-256`.
It is crucial change the `hmac_key` to a random value. This key is used to sign the challenge and the response,
so it must be treated as a secret within your application.
The `num_range` option specifies the range of numbers to use in the challenge and determines the difficulty of the proof-of-work.
For an explanation of the `timeout` option see below.

## Challenge expiration

The current time of the server is included in the salt of the challenge. When the client responds, it has to send the
same salt back, so the server can determine when the challenge was issued. The `timeout` option in the initializer file
specifies the time that a challenge is valid. If the response is received after the timeout, the verification will fail.

As users might complete the captcha before filling out a complex form, the `timeout` should be set to a reasonable
value.

## Replay attacks

To also guard against replay attacks within the configured `timeout` period, the gem uses a model named `AltchaSolution` to
store completed responses. A unique constraint is added to the database to prevent the same response from being stored.

As these stored solutions are useless after the `timeout` period, the `AltchaSolution.cleanup` convenience function
should be called regularly.

## Usage

You need to include the ALTCHA javascript widget in your application's asset pipeline. This is not done by the gem
at this point. Read up on the [ALTCHA documentation](https://altcha.org/docs/website-integration) for more information.

Then add the following code to the form you want to protect:

```erb
<altcha-widget challengeurl="<%= altcha_url() %>"></altcha-widget>
```

Once the user clicks the checkbox, the widget will send a request to the server to get a new challenge.
When the user-side code inside the widget found the solution to the challenge, the spinner will stop
and a hidden input field with the name `altcha` will be created to convey the solution as base64
encoded JSON dictionary.

In the controller that handles the form submission, you can verify the response with the following code:

```ruby
def create
  @model = Model.new(model_params)

  unless AltchaSolution.verify_and_save(params.permit(:altcha)[:altcha])
    flash.now[:alert] = 'ALTCHA verification failed.'
    render :new, status: :unprocessable_entity
    return
  end

  # ...
end
```

The `verify_and_save` method will return `true` if the response is valid and has not been used before.

## Contributing

Bug reports and pull requests are welcome.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
