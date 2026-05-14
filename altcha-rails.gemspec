# frozen_string_literal: true

Gem::Specification.new do |s|
  s.name        = "altcha-rails"
  s.version     = "0.1.0"
  s.authors     = ["Daniel Mack"]
  s.email       = "altcha-rails.gem@zonque.org"
  s.homepage    = "https://github.com/zonque/altcha-rails"
  s.metadata    = { "source_code_uri" => "https://github.com/zonque/altcha-rails" }
  s.summary     = "Ruby library for ALTCHA"
  s.description = "ALTCHA is a free, open-source CAPTCHA alternative that protects your website from spam and abuse. This gem implements the ALTCHA v1 challenge protocol (challenge creation and submission verification) and integrates with Rails.cache for replay protection."
  s.licenses    = ["MIT"]

  s.required_ruby_version = ">= 3.0"

  s.require_paths = ["lib"]
  s.files = `git ls-files`.split("\n")

  # base64 is no longer a default gem as of Ruby 3.4.
  s.add_runtime_dependency "base64", "~> 0.2"

  s.add_development_dependency "minitest", "~> 5.0"
  s.add_development_dependency "rake", "~> 13.0"

  s.specification_version = 4
end
