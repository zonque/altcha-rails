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
  config.hmac_key         = ENV.fetch('ALTCHA_HMAC_KEY')
  config.algorithm        = 'SHA-256'             # default
  config.max_number       = 1_000_000             # difficulty: upper bound for the proof-of-work nonce. default 1_000_000
  config.timeout          = 5.minutes             # default 300 seconds; accepts integers or ActiveSupport durations
  config.cache_key_prefix = 'altcha:solution:'    # default; prepended to the Rails.cache key used for replay protection
end
```

`hmac_key` has no default — it must be set explicitly. The other options have the defaults shown above.

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

## Development

```
bundle install
bundle exec rake test
```

Tests use Minitest and a small `FakeCache` shim that mimics the bits of `Rails.cache` the gem touches, so the suite runs without booting Rails.

## Changelog

### 0.1.0

This release is a substantial rework. The public API collapses to two module methods, and everything else (model, migration, controller, route, generator) is gone.

**Highlights:**

- **Security fix — [CVE-2025-68113](https://altcha.org/security-advisory/) (challenge splicing / replay).** Salt now follows the canonical v1 ALTCHA format `<random_hex>?expires=<unix_seconds>&`, and `Altcha.verify` normalises the salt to its trailing-`&` form before recomputing the proof-of-work hash. A spliced salt no longer round-trips to the same digest.
- **No more `AltchaSolution` ActiveRecord model or `altcha_solutions` table.** Replay protection lives in `Rails.cache` (keyed by the submission's HMAC signature, TTL = `Altcha.timeout`, atomic via `unless_exist: true`).
- **No more generated controller or route.** The widget now accepts the challenge JSON inline via its `challenge` attribute, so the host application no longer needs an endpoint to serve challenges.
- **No more `rails generate altcha:install` generator.** Configuration is one `Altcha.setup` block — see [Configuration](#configuration) above.
- **Configuration knob renamed**: `num_range` (Range) → `max_number` (Integer). `hmac_key` no longer has a placeholder default and must be set explicitly. A new `cache_key_prefix` option (default `"altcha:solution:"`) lets you namespace the replay-tracking keys.

#### Upgrade guide from 0.0.x

**1. Confirm your cache backend.** It must be shared across all server processes. In production: `:redis_cache_store`, `:mem_cache_store`, `:solid_cache_store`, `:file_store`, or another shared backend. The default `:memory_store` is per-process and is unsafe here; `:null_store` disables replay protection entirely. See the [Challenge expiration](#challenge-expiration) section.

**2. Delete the generated model:**

```
rm app/models/altcha_solution.rb
```

If you have specs covering it, remove those too.

**3. Delete the generated controller:**

```
rm app/controllers/altcha_controller.rb
```

If you have specs or request tests covering it, remove those too.

**4. Remove the route.** In `config/routes.rb`, delete the line:

```ruby
get '/altcha', to: 'altcha#new'
```

**5. Update your view to inline the challenge JSON.** Replace:

```erb
<altcha-widget challengeurl="<%= altcha_url %>"></altcha-widget>
```

with:

```erb
<altcha-widget challenge='<%= Altcha.create_challenge.to_json %>'></altcha-widget>
```

The `challenge` attribute is part of the modern ALTCHA widget; the `challengeurl` round-trip is no longer required.

**6. Generate a migration to drop the `altcha_solutions` table:**

```
$ rails generate migration DropAltchaSolutions
```

Fill in the generated file as follows (the `down` block is provided so the migration is reversible — adjust the column list if your installation customised it):

```ruby
class DropAltchaSolutions < ActiveRecord::Migration[7.1]
  def up
    drop_table :altcha_solutions
  end

  def down
    create_table :altcha_solutions do |t|
      t.string  :algorithm
      t.string  :challenge
      t.string  :salt
      t.string  :signature
      t.integer :number

      t.timestamps
    end

    add_index :altcha_solutions,
              [:algorithm, :challenge, :salt, :signature, :number],
              unique: true,
              name: 'index_altcha_solutions'
  end
end
```

Then run `rails db:migrate`.

**7. Replace the verification call.** The public API moves from the generated model to the gem itself. The return value flips from boolean to `Altcha::Submission`-or-`nil`, but the truthy/falsy semantics are unchanged:

```ruby
# Before (0.0.x):
unless AltchaSolution.verify_and_save(params.permit(:altcha)[:altcha])
  flash.now[:alert] = 'ALTCHA verification failed.'
  render :new, status: :unprocessable_entity
  return
end

# After (0.1.0):
unless Altcha.verify(params.permit(:altcha)[:altcha])
  flash.now[:alert] = 'ALTCHA verification failed.'
  render :new, status: :unprocessable_entity
  return
end
```

**8. Remove `AltchaSolution.cleanup` calls.** Cache entries now expire automatically via `expires_in: Altcha.timeout`, so any scheduled job, rake task, or cron entry that called `AltchaSolution.cleanup` can be deleted.

**9. Update your initializer.** Rename `num_range` to `max_number` (and switch from a Range to an Integer) and remove any placeholder `hmac_key = 'change-me'`:

```ruby
# Before (0.0.x):
Altcha.setup do |config|
  config.algorithm = 'SHA-256'
  config.num_range = (50_000..500_000)
  config.timeout   = 5.minutes
  config.hmac_key  = 'change-me'
end

# After (0.1.0):
Altcha.setup do |config|
  config.hmac_key   = ENV.fetch('ALTCHA_HMAC_KEY')
  config.max_number = 500_000
  config.timeout    = 5.minutes
end
```

## Contributing

Bug reports and pull requests are welcome.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
