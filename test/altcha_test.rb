# frozen_string_literal: true

require "test_helper"

class AltchaTest < Minitest::Test
  HMAC_KEY = "test-secret-key"

  def setup
    @prev_hmac_key   = Altcha.hmac_key
    @prev_timeout    = Altcha.timeout
    @prev_max_number = Altcha.max_number
    @prev_algorithm  = Altcha.algorithm
    @prev_prefix     = Altcha.cache_key_prefix

    Altcha.hmac_key         = HMAC_KEY
    Altcha.timeout          = 300
    Altcha.max_number       = 1_000
    Altcha.algorithm        = "SHA-256"
    Altcha.cache_key_prefix = "altcha:solution:"

    Rails.cache.clear
  end

  def teardown
    Altcha.hmac_key         = @prev_hmac_key
    Altcha.timeout          = @prev_timeout
    Altcha.max_number       = @prev_max_number
    Altcha.algorithm        = @prev_algorithm
    Altcha.cache_key_prefix = @prev_prefix
  end

  # -- helpers --------------------------------------------------------------

  def encode(hash)
    Base64.strict_encode64(hash.to_json)
  end

  def solve(challenge)
    (0..Altcha.max_number).find do |n|
      Digest::SHA256.hexdigest(challenge.salt + n.to_s) == challenge.challenge
    end
  end

  def payload_for(challenge, number)
    {
      "algorithm" => challenge.algorithm,
      "challenge" => challenge.challenge,
      "number"    => number,
      "salt"      => challenge.salt,
      "signature" => challenge.signature,
    }
  end

  def solved_payload
    ch = Altcha.create_challenge
    [ch, encode(payload_for(ch, solve(ch)))]
  end

  # -- Altcha.create_challenge ---------------------------------------------

  def test_create_challenge_returns_challenge_with_required_fields
    ch = Altcha.create_challenge
    assert_equal "SHA-256", ch.algorithm
    assert_equal 1_000, ch.max_number
    refute_nil ch.salt
    refute_nil ch.challenge
    refute_nil ch.signature
  end

  def test_create_challenge_salt_uses_canonical_v1_format
    ch = Altcha.create_challenge
    assert_match(/\A[0-9a-f]{24}\?expires=\d+&\z/, ch.salt,
                 "salt must be `<hex>?expires=<unix>&` (CVE-2025-68113 mitigation)")
  end

  def test_create_challenge_signature_is_hmac_of_challenge_with_configured_key
    ch = Altcha.create_challenge
    expected = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("SHA-256"), HMAC_KEY, ch.challenge)
    assert_equal expected, ch.signature
  end

  def test_create_challenge_challenge_field_is_sha256_of_salt_plus_secret
    ch = Altcha.create_challenge
    n = solve(ch)
    refute_nil n, "solver could not find secret within max_number"
    assert_equal ch.challenge, Digest::SHA256.hexdigest(ch.salt + n.to_s)
  end

  def test_create_challenge_to_json_emits_widget_compatible_payload
    json = JSON.parse(Altcha.create_challenge.to_json)
    assert_equal %w[algorithm challenge maxnumber salt signature], json.keys.sort
    assert_equal "SHA-256", json["algorithm"]
    assert_equal 1_000, json["maxnumber"]
  end

  def test_create_challenge_raises_when_hmac_key_is_nil
    Altcha.hmac_key = nil
    assert_raises(Altcha::ConfigurationError) { Altcha.create_challenge }
  end

  def test_create_challenge_raises_when_hmac_key_is_empty
    Altcha.hmac_key = ""
    assert_raises(Altcha::ConfigurationError) { Altcha.create_challenge }
  end

  def test_create_challenge_accepts_per_call_overrides
    explicit_expires = Time.now.to_i + 9999
    ch = Altcha.create_challenge(expires: explicit_expires, number: 42, max_number: 100)
    assert_match(/\?expires=#{explicit_expires}&\z/, ch.salt)
    assert_equal 100, ch.max_number
    assert_equal ch.challenge, Digest::SHA256.hexdigest(ch.salt + "42")
  end

  # -- Altcha.verify: happy path -------------------------------------------

  def test_verify_accepts_a_valid_fresh_submission
    ch, b64 = solved_payload
    submission = Altcha.verify(b64)
    refute_nil submission
    assert_kind_of Altcha::Submission, submission
    assert_equal ch.signature, submission.signature
  end

  # -- Altcha.verify: replay protection ------------------------------------

  def test_verify_rejects_a_replay_of_the_same_submission
    _ch, b64 = solved_payload
    refute_nil Altcha.verify(b64), "first submission must be accepted"
    assert_nil Altcha.verify(b64), "replay must be rejected"
  end

  def test_verify_writes_to_cache_under_the_signature_keyed_prefix
    ch, b64 = solved_payload
    Altcha.verify(b64)
    assert_equal true, Rails.cache.read("altcha:solution:#{ch.signature}")
  end

  def test_verify_honours_configured_cache_key_prefix
    Altcha.cache_key_prefix = "myapp:altcha:"
    ch, b64 = solved_payload
    Altcha.verify(b64)
    assert_equal true, Rails.cache.read("myapp:altcha:#{ch.signature}")
    assert_nil Rails.cache.read("altcha:solution:#{ch.signature}")
  end

  def test_verify_passes_timeout_through_as_expires_in
    Altcha.timeout = 42
    ch, b64 = solved_payload
    Altcha.verify(b64)
    entry = Rails.cache.entry("altcha:solution:#{ch.signature}")
    assert_equal 42, entry[:expires_in]
  end

  def test_verify_does_not_touch_cache_when_crypto_check_fails
    bad = "not-a-real-payload"
    Altcha.verify(bad)
    assert_empty Rails.cache.keys
  end

  # -- Altcha.verify: failure modes (crypto) -------------------------------

  def test_verify_returns_nil_on_garbage_input
    assert_nil Altcha.verify("garbage!!!!")
    assert_nil Altcha.verify("")
    assert_nil Altcha.verify(nil)
  end

  def test_verify_returns_nil_when_payload_is_not_a_hash
    assert_nil Altcha.verify(Base64.strict_encode64('"a string"'))
    assert_nil Altcha.verify(Base64.strict_encode64("123"))
    assert_nil Altcha.verify(Base64.strict_encode64("[]"))
  end

  def test_verify_rejects_wrong_algorithm
    ch = Altcha.create_challenge
    n = solve(ch)
    p = payload_for(ch, n).merge("algorithm" => "SHA-512")
    assert_nil Altcha.verify(encode(p))
  end

  def test_verify_rejects_non_integer_number
    ch = Altcha.create_challenge
    n = solve(ch)
    p = payload_for(ch, n).merge("number" => n.to_s)
    assert_nil Altcha.verify(encode(p))
  end

  def test_verify_rejects_tampered_number
    ch = Altcha.create_challenge
    n = solve(ch)
    p = payload_for(ch, n + 1)
    assert_nil Altcha.verify(encode(p))
  end

  def test_verify_rejects_tampered_challenge
    ch = Altcha.create_challenge
    n = solve(ch)
    p = payload_for(ch, n).merge("challenge" => "0" * ch.challenge.length)
    assert_nil Altcha.verify(encode(p))
  end

  def test_verify_rejects_tampered_signature
    ch = Altcha.create_challenge
    n = solve(ch)
    p = payload_for(ch, n).merge("signature" => "0" * ch.signature.length)
    assert_nil Altcha.verify(encode(p))
  end

  def test_verify_rejects_expired_challenge
    Altcha.timeout = -1
    ch = Altcha.create_challenge
    Altcha.timeout = 300
    n = solve(ch)
    assert_nil Altcha.verify(encode(payload_for(ch, n)))
  end

  def test_verify_rejects_salt_without_expires_parameter
    salt = "#{SecureRandom.hex(12)}&"
    challenge = Digest::SHA256.hexdigest(salt + "42")
    signature = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("SHA-256"), HMAC_KEY, challenge)
    p = {
      "algorithm" => "SHA-256",
      "challenge" => challenge,
      "number"    => 42,
      "salt"      => salt,
      "signature" => signature,
    }
    assert_nil Altcha.verify(encode(p))
  end

  def test_verify_rejects_when_hmac_key_not_configured
    _ch, b64 = solved_payload
    Altcha.hmac_key = nil
    assert_nil Altcha.verify(b64)
  end

  # -- CVE-2025-68113 regression -------------------------------------------

  def test_verify_rejects_parameter_splice_attack
    # Construct a hash-colliding splice. Without the trailing-'&' normalisation
    # in valid?, this submission would be accepted:
    #   SHA256(salt + "1" + "23") == SHA256(salt + "123")
    salt = "abc123def456abc123def456?expires=#{Time.now.to_i + 60}&"
    legitimate_hash = Digest::SHA256.hexdigest(salt + "123")
    signature = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("SHA-256"), HMAC_KEY, legitimate_hash)

    # Sanity: prove the collision exists before testing rejection.
    assert_equal legitimate_hash, Digest::SHA256.hexdigest((salt + "1") + "23"),
                 "splice precondition: hash collision must exist for this test to be meaningful"

    spliced = {
      "algorithm" => "SHA-256",
      "challenge" => legitimate_hash,
      "number"    => 23,
      "salt"      => salt + "1",
      "signature" => signature,
    }
    assert_nil Altcha.verify(encode(spliced)),
               "CVE-2025-68113: spliced submission must be rejected"
  end

  # -- Altcha.setup --------------------------------------------------------

  def test_setup_yields_the_module
    yielded = nil
    Altcha.setup { |c| yielded = c }
    assert_same Altcha, yielded
  end

  def test_setup_assignments_persist
    Altcha.setup do |c|
      c.max_number = 7777
      c.timeout = 60
    end
    assert_equal 7777, Altcha.max_number
    assert_equal 60, Altcha.timeout
  end
end
