# frozen_string_literal: true

module Altcha
  mattr_accessor :configured
  @@configured = false

  mattr_accessor :algorithm
  @@algorithm = 'SHA-256'

  mattr_accessor :num_range
  @@num_range = (50_000..500_000)

  mattr_accessor :hmac_key
  @@hmac_key = "change-me"

  mattr_accessor :timeout
  @@timeout = 5.minutes

  def self.setup
    @@configured = true
    yield self
  end

  def self.create_challenge
    Challenge.create
  end

  def self.verify(base64encoded)
    raise "Altcha not configured" unless Altcha.configured

    payload = JSON.parse(Base64.decode64(base64encoded)) rescue nil
    return nil if payload.nil?

    submission = Submission.new(payload)
    return nil unless submission.valid?

    if Rails.cache.write("altcha:solution:#{submission.signature}", true,
                         expires_in: Altcha.timeout, unless_exist: true)
      submission
    else
      nil
    end
  end

  class Challenge
    attr_accessor :algorithm, :challenge, :salt, :signature, :max_number

    def self.create
      raise "Altcha not configured" unless Altcha.configured

      secret_number = rand(Altcha.num_range)
      expires = Time.now.to_i + Altcha.timeout.to_i

      a = Challenge.new
      a.algorithm = Altcha.algorithm
      a.max_number = Altcha.num_range.max
      # Canonical v1 ALTCHA salt: random hex, expires parameter, trailing '&'
      # to delimit the parameter list from the nonce (CVE-2025-68113).
      a.salt = "#{SecureRandom.hex(12)}?expires=#{expires}&"
      a.challenge = Digest::SHA256.hexdigest(a.salt + secret_number.to_s)
      a.signature = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new(a.algorithm), Altcha.hmac_key, a.challenge)

      return a
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
    attr_accessor :algorithm, :challenge, :salt, :signature, :number

    def initialize(v = {})
      @algorithm = v["algorithm"] || ""
      @challenge = v["challenge"] || ""
      @signature = v["signature"] || ""
      @salt      = v["salt"]      || ""
      @number    = v["number"]    || 0
    end

    def valid?
      return false unless @algorithm == Altcha.algorithm
      return false unless @number.is_a?(Integer)

      expires = extract_expires(@salt)
      return false if expires.nil?
      return false unless Time.at(expires) > Time.now

      # Normalize to canonical trailing-'&' form before recomputing the hash;
      # a spliced salt no longer round-trips to the same digest. Mitigates
      # CVE-2025-68113.
      canonical_salt = @salt.end_with?('&') ? @salt : "#{@salt}&"
      check = Digest::SHA256.hexdigest(canonical_salt + @number.to_s)

      return false unless @challenge == check

      expected_sig = OpenSSL::HMAC.hexdigest(
        OpenSSL::Digest.new(@algorithm), Altcha.hmac_key, check
      )
      secure_compare(@signature, expected_sig)
    end

    private

    def extract_expires(salt)
      query = salt.split('?', 2)[1]
      return nil unless query

      query.split('&').each do |pair|
        key, value = pair.split('=', 2)
        return Integer(value, 10) if key == 'expires' && value
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
