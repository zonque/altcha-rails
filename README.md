[![Gem Version](https://badge.fury.io/rb/altcha-rails.svg)](https://badge.fury.io/rb/altcha-rails)

# Ruby gem for ALTCHA

[ALTCHA](https://altcha.org/) is a protocol designed for safeguarding against spam and abuse by utilizing a proof-of-work mechanism. This protocol comprises both a client-facing widget and a server-side verification process.

`altcha-rails` is a Ruby gem that provides a simple way to integrate ALTCHA into your Ruby on Rails application.

The gem provides two module methods: `Altcha.create_challenge`, which produces a fresh challenge for the form, and `Altcha.verify`, which validates the widget's submission and records it in `Rails.cache` for replay protection.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'altcha-rails'
```

Then execute `bundle install`.

## Configuration

Create `config/initializers/altcha.rb` with the following configuration options:

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

Each challenge embeds an `expires` parameter in its salt — a Unix timestamp set to `Time.now + Altcha.timeout`.
When the client responds, the server rejects the submission if that timestamp has passed.

The salt is laid out in the canonical v1 ALTCHA format — `<random_hex>?expires=<unix_seconds>&` — including the
trailing `&` delimiter that closes the parameter list before the proof-of-work nonce is appended for hashing. This
delimiter is required by the protocol fix for [CVE-2025-68113](https://altcha.org/security-advisory/) and is enforced
by `Altcha.verify`.

As users might complete the captcha before filling out a complex form, the `timeout` should be set to a reasonable
value.

## Replay attacks

To also guard against replay attacks within the configured `timeout` period, the gem records each accepted
solution in `Rails.cache`, keyed by the solution's HMAC signature. Entries are written with `expires_in: Altcha.timeout`
and `unless_exist: true`, so a replayed submission within the timeout window is rejected atomically, and entries
expire automatically once the timeout has passed. No periodic cleanup is required.

Make sure `Rails.cache` is configured to use a backend that is shared across all server processes (e.g.
`:redis_cache_store`, `:mem_cache_store`, `:solid_cache_store`, or `:file_store`). The default `:memory_store` is
per-process and would let a replay slip through on a different worker; `:null_store` disables replay protection
entirely.

## Issuing a challenge

`Altcha.create_challenge` returns an `Altcha::Challenge` whose `#to_json` produces exactly the payload the widget expects. The widget accepts this JSON directly via its `challenge` attribute, so no separate `/altcha` route is needed:

```erb
<altcha-widget challenge='<%= Altcha.create_challenge.to_json %>'></altcha-widget>
```

Include the ALTCHA javascript widget script in your asset pipeline; see [the ALTCHA documentation](https://altcha.org/docs/website-integration) for the widget itself.

## Verifying a submission

When the form is submitted, the widget sends a base64-encoded JSON payload in a hidden input named `altcha`. In the controller that handles the submission, verify it with:

```ruby
def create
  @model = Model.create(model_params)

  unless Altcha.verify(params.permit(:altcha)[:altcha])
    flash.now[:alert] = 'ALTCHA verification failed.'
    render :new, status: :unprocessable_entity
    return
  end

  # ...
end
```

`Altcha.verify` returns the `Altcha::Submission` if the response is valid and has not been seen before within the
timeout window, and `nil` otherwise.

## Contributing

Bug reports and pull requests are welcome.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
