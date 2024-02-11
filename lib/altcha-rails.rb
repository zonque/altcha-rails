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

  class Challenge
    attr_accessor :algorithm, :challenge, :salt, :signature

    def self.create
      raise "Altcha not configured" unless Altcha.configured

      secret_number = rand(Altcha.num_range)

      a = Challenge.new
      a.algorithm = Altcha.algorithm
      a.salt = [Time.now.to_s, SecureRandom.hex(12)].join('|')
      a.challenge = Digest::SHA256.hexdigest(a.salt + secret_number.to_s)
      a.signature = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new(a.algorithm), Altcha.hmac_key, a.challenge)

      return a
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
      check = Digest::SHA256.hexdigest(@salt + @number.to_s)

      parts = @salt.split('|')
      t = Time.parse(parts[0]) rescue nil

      return @algorithm == Altcha.algorithm &&
        @challenge == check &&
        @signature == OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new(Altcha.algorithm), Altcha.hmac_key, check) &&
        t.present? && t > Time.now - Altcha.timeout && t < Time.now
    end
  end
end
