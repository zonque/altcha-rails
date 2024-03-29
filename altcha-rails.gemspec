# frozen_string_literal: true

Gem::Specification.new do |s|
  s.name = "altcha-rails"
  s.version = "0.0.5"
  s.authors = ["Daniel Mack"]
  s.homepage = "https://github.com/zonque/altcha-rails"
  s.metadata = { "source_code_uri" => "https://github.com/zonque/altcha-rails" }
  s.summary = "Rails helpers for ALTCHA"
  s.description = "ALTCHA is a free, open-source CAPTCHA alternative that protects your website from spam and abuse"
  s.email = "altcha-rails.gem@zonque.org"
  s.require_paths = ["lib"]
  s.files = `git ls-files`.split("\n")
  s.licenses = ["MIT"]
  s.specification_version = 4
end
