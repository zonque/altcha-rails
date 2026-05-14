# frozen_string_literal: true

require "base64"
require "digest"
require "json"
require "openssl"
require "securerandom"

module Altcha
  class ConfigurationError < StandardError; end

  class << self
    attr_accessor :algorithm, :max_number, :hmac_key, :timeout, :cache_key_prefix
  end

  self.algorithm        = "SHA-256"
  self.max_number       = 1_000_000
  self.hmac_key         = nil
  self.timeout          = 300 # seconds; accepts anything responding to #to_i
  self.cache_key_prefix = "altcha:solution:"

  def self.setup
    yield self
  end

  # Returns an Altcha::Challenge. Its #to_json produces the payload the
  # widget expects via the `challenge` attribute.
  def self.create_challenge(**options)
    Challenge.create(**options)
  end

  # Verifies a base64-encoded JSON submission AND records it in Rails.cache
  # for replay protection (atomic via `unless_exist: true`, TTL = timeout).
  # Returns the Altcha::Submission on a fresh accept, nil on failure (invalid
  # crypto, expired, spliced, or replay within the timeout window).
  def self.verify(base64_string)
    submission = Submission.verify(base64_string)
    return nil unless submission

    if Rails.cache.write("#{cache_key_prefix}#{submission.signature}", true,
                         expires_in: timeout, unless_exist: true)
      submission
    else
      nil # replay
    end
  end

  class Challenge
    attr_accessor :algorithm, :challenge, :salt, :signature, :max_number

    def self.create(algorithm: nil, hmac_key: nil, max_number: nil, expires: nil, number: nil)
      hmac_key ||= Altcha.hmac_key
      raise ConfigurationError, "Altcha.hmac_key is not set" if hmac_key.nil? || hmac_key.empty?

      algorithm  ||= Altcha.algorithm
      max_number ||= Altcha.max_number
      expires    ||= Time.now.to_i + Altcha.timeout.to_i
      number     ||= SecureRandom.random_number(max_number)

      ch = new
      ch.algorithm  = algorithm
      ch.max_number = max_number
      # Canonical v1 ALTCHA salt: random hex, expires parameter, trailing '&'
      # to delimit the parameter list from the nonce (CVE-2025-68113).
      ch.salt       = "#{SecureRandom.hex(12)}?expires=#{expires.to_i}&"
      ch.challenge  = Digest::SHA256.hexdigest(ch.salt + number.to_s)
      ch.signature  = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new(algorithm), hmac_key, ch.challenge)
      ch
    end

    def to_h
      {
        algorithm: algorithm,
        challenge: challenge,
        maxnumber: max_number,
        salt: salt,
        signature: signature,
      }
    end

    def to_json(*args)
      to_h.to_json(*args)
    end
  end

  class Submission
    attr_reader :algorithm, :challenge, :salt, :signature, :number

    def self.verify(base64_string)
      raw = begin
        Base64.decode64(base64_string.to_s)
      rescue ArgumentError
        return nil
      end
      payload = JSON.parse(raw) rescue nil
      return nil unless payload.is_a?(Hash)

      submission = new(payload)
      submission.valid? ? submission : nil
    end

    def initialize(payload = {})
      @algorithm = payload["algorithm"].to_s
      @challenge = payload["challenge"].to_s
      @signature = payload["signature"].to_s
      @salt      = payload["salt"].to_s
      @number    = payload["number"]
    end

    def valid?
      return false unless @algorithm == Altcha.algorithm
      return false unless @number.is_a?(Integer)
      return false if Altcha.hmac_key.nil? || Altcha.hmac_key.empty?

      expires = extract_expires(@salt)
      return false if expires.nil?
      return false unless Time.at(expires) > Time.now

      # Normalize to canonical trailing-'&' form before recomputing the hash;
      # a spliced salt no longer round-trips to the same digest. Mitigates
      # CVE-2025-68113.
      canonical_salt = @salt.end_with?("&") ? @salt : "#{@salt}&"
      check = Digest::SHA256.hexdigest(canonical_salt + @number.to_s)

      return false unless @challenge == check

      expected_sig = OpenSSL::HMAC.hexdigest(
        OpenSSL::Digest.new(@algorithm), Altcha.hmac_key, check
      )
      secure_compare(@signature, expected_sig)
    end

    private

    def extract_expires(salt)
      query = salt.split("?", 2)[1]
      return nil unless query

      query.split("&").each do |pair|
        key, value = pair.split("=", 2)
        return Integer(value, 10) if key == "expires" && value
      end
      nil
    rescue ArgumentError
      nil
    end

    def secure_compare(a, b)
      return false unless a.bytesize == b.bytesize

      diff = 0
      a.bytes.zip(b.bytes) { |x, y| diff |= x ^ y }
      diff.zero?
    end
  end
end
